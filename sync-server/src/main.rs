use anyhow::{Context, Result};
use axum::{
    extract::{DefaultBodyLimit, State},
    http::{header, HeaderMap, HeaderValue, StatusCode},
    response::{IntoResponse, Response},
    routing::get,
    Json, Router,
};
use rusqlite::{params, Connection, OptionalExtension, TransactionBehavior};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{
    env,
    net::SocketAddr,
    path::{Path, PathBuf},
    sync::{Arc, Mutex, MutexGuard},
    time::{SystemTime, UNIX_EPOCH},
};
use subtle::ConstantTimeEq;
use tracing::{info, warn};

const MAX_ENVELOPE_FIELD: usize = 350_000;

#[derive(Clone)]
struct AppState {
    store: Arc<Mutex<Store>>,
}

struct Store {
    db: Connection,
    token_hash: [u8; 32],
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct VaultEnvelope {
    schema_version: u32,
    nonce: String,
    ciphertext: String,
}

#[derive(Serialize)]
struct VaultResponse {
    revision: u64,
    updated_at: u64,
    envelope: VaultEnvelope,
}

#[derive(Serialize)]
struct ErrorBody {
    error: &'static str,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct RotateCredentialsRequest {
    new_token: String,
    envelope: VaultEnvelope,
}

enum ApiError {
    Unauthorized,
    Missing,
    Conflict,
    Invalid(&'static str),
    Internal,
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let (status, message) = match self {
            Self::Unauthorized => (StatusCode::UNAUTHORIZED, "unauthorized"),
            Self::Missing => (StatusCode::NOT_FOUND, "vault_not_found"),
            Self::Conflict => (StatusCode::CONFLICT, "revision_conflict"),
            Self::Invalid(message) => (StatusCode::BAD_REQUEST, message),
            Self::Internal => (StatusCode::INTERNAL_SERVER_ERROR, "internal_error"),
        };
        let mut response = (status, Json(ErrorBody { error: message })).into_response();
        response
            .headers_mut()
            .insert(header::CACHE_CONTROL, HeaderValue::from_static("no-store"));
        if status == StatusCode::UNAUTHORIZED {
            response.headers_mut().insert(
                header::WWW_AUTHENTICATE,
                HeaderValue::from_static("Bearer realm=\"tokenplan-sync\""),
            );
        }
        response
    }
}

fn token_hash(value: &str) -> [u8; 32] {
    Sha256::digest(value.as_bytes()).into()
}

fn authorize<'a>(
    headers: &HeaderMap,
    state: &'a AppState,
) -> Result<MutexGuard<'a, Store>, ApiError> {
    let supplied = headers
        .get(header::AUTHORIZATION)
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.strip_prefix("Bearer "))
        .filter(|value| !value.is_empty())
        .ok_or(ApiError::Unauthorized)?;
    let store = state.store.lock().map_err(|_| ApiError::Internal)?;
    if bool::from(token_hash(supplied).ct_eq(&store.token_hash)) {
        Ok(store)
    } else {
        Err(ApiError::Unauthorized)
    }
}

fn initialize_database(path: &Path) -> Result<Connection> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)
            .with_context(|| format!("create database directory {}", parent.display()))?;
    }
    let connection =
        Connection::open(path).with_context(|| format!("open database {}", path.display()))?;
    initialize_connection(&connection)?;
    Ok(connection)
}

fn initialize_connection(connection: &Connection) -> Result<()> {
    connection.execute_batch(
        "PRAGMA journal_mode=WAL;
         PRAGMA synchronous=FULL;
         CREATE TABLE IF NOT EXISTS vault (
             id INTEGER PRIMARY KEY CHECK (id = 1),
             revision INTEGER NOT NULL,
             updated_at INTEGER NOT NULL,
             envelope TEXT NOT NULL
         );
         CREATE TABLE IF NOT EXISTS sync_settings (
             key TEXT PRIMARY KEY,
             value BLOB NOT NULL
         );",
    )?;
    Ok(())
}

fn app(connection: Connection, token: &str) -> Result<Router> {
    let persisted: Option<Vec<u8>> = connection
        .query_row(
            "SELECT value FROM sync_settings WHERE key = 'token_hash'",
            [],
            |row| row.get(0),
        )
        .optional()?;
    let persisted = match persisted {
        Some(value) => value
            .try_into()
            .map_err(|_| anyhow::anyhow!("stored authentication hash is invalid"))?,
        None => {
            let value = token_hash(token);
            connection.execute(
                "INSERT INTO sync_settings (key, value) VALUES ('token_hash', ?1)",
                params![value.as_slice()],
            )?;
            value
        }
    };
    let state = AppState {
        store: Arc::new(Mutex::new(Store {
            db: connection,
            token_hash: persisted,
        })),
    };
    Ok(Router::new()
        .route("/healthz", get(health))
        .route("/api/v1/vault", get(get_vault).put(put_vault))
        .route(
            "/api/v1/vault/credentials",
            axum::routing::put(rotate_credentials),
        )
        .layer(DefaultBodyLimit::max(256 * 1024))
        .with_state(state))
}

async fn health() -> impl IntoResponse {
    (
        [(header::CACHE_CONTROL, "no-store")],
        Json(serde_json::json!({"status": "ok"})),
    )
}

async fn get_vault(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<Response, ApiError> {
    let store = authorize(&headers, &state)?;
    let row: Option<(u64, u64, String)> = store
        .db
        .query_row(
            "SELECT revision, updated_at, envelope FROM vault WHERE id = 1",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .optional()
        .map_err(|error| {
            warn!(%error, "vault read failed");
            ApiError::Internal
        })?;
    let (revision, updated_at, serialized) = row.ok_or(ApiError::Missing)?;
    let envelope: VaultEnvelope = serde_json::from_str(&serialized).map_err(|error| {
        warn!(%error, "stored vault envelope is invalid");
        ApiError::Internal
    })?;
    let mut response = Json(VaultResponse {
        revision,
        updated_at,
        envelope,
    })
    .into_response();
    response.headers_mut().insert(
        header::ETAG,
        HeaderValue::from_str(&format!("\"{revision}\"")).map_err(|_| ApiError::Internal)?,
    );
    response
        .headers_mut()
        .insert(header::CACHE_CONTROL, HeaderValue::from_static("no-store"));
    Ok(response)
}

fn parse_revision(headers: &HeaderMap) -> Result<u64, ApiError> {
    let raw = headers
        .get(header::IF_MATCH)
        .and_then(|value| value.to_str().ok())
        .ok_or(ApiError::Invalid("if_match_required"))?;
    raw.trim_matches('"')
        .parse()
        .map_err(|_| ApiError::Invalid("invalid_if_match"))
}

fn validate_envelope(envelope: &VaultEnvelope) -> Result<(), ApiError> {
    if envelope.schema_version == 0 {
        return Err(ApiError::Invalid("invalid_schema_version"));
    }
    if envelope.nonce.is_empty()
        || envelope.ciphertext.is_empty()
        || envelope.nonce.len() > MAX_ENVELOPE_FIELD
        || envelope.ciphertext.len() > MAX_ENVELOPE_FIELD
    {
        return Err(ApiError::Invalid("invalid_envelope"));
    }
    Ok(())
}

async fn put_vault(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(envelope): Json<VaultEnvelope>,
) -> Result<Response, ApiError> {
    validate_envelope(&envelope)?;
    let expected = parse_revision(&headers)?;
    let serialized = serde_json::to_string(&envelope).map_err(|_| ApiError::Internal)?;
    let updated_at = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|_| ApiError::Internal)?
        .as_secs();

    let mut store = authorize(&headers, &state)?;
    let transaction = store
        .db
        .transaction_with_behavior(TransactionBehavior::Immediate)
        .map_err(|error| {
            warn!(%error, "vault transaction failed");
            ApiError::Internal
        })?;
    let current: u64 = transaction
        .query_row("SELECT revision FROM vault WHERE id = 1", [], |row| {
            row.get(0)
        })
        .optional()
        .map_err(|_| ApiError::Internal)?
        .unwrap_or(0);
    if current != expected {
        return Err(ApiError::Conflict);
    }
    let revision = current.checked_add(1).ok_or(ApiError::Internal)?;
    transaction
        .execute(
            "INSERT INTO vault (id, revision, updated_at, envelope) VALUES (1, ?1, ?2, ?3)
             ON CONFLICT(id) DO UPDATE SET revision = excluded.revision,
               updated_at = excluded.updated_at, envelope = excluded.envelope",
            params![revision, updated_at, serialized],
        )
        .map_err(|error| {
            warn!(%error, "vault update failed");
            ApiError::Internal
        })?;
    transaction.commit().map_err(|_| ApiError::Internal)?;

    let mut response = (
        StatusCode::OK,
        Json(serde_json::json!({"revision": revision, "updated_at": updated_at})),
    )
        .into_response();
    response.headers_mut().insert(
        header::ETAG,
        HeaderValue::from_str(&format!("\"{revision}\"")).map_err(|_| ApiError::Internal)?,
    );
    response
        .headers_mut()
        .insert(header::CACHE_CONTROL, HeaderValue::from_static("no-store"));
    Ok(response)
}

async fn rotate_credentials(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(request): Json<RotateCredentialsRequest>,
) -> Result<Response, ApiError> {
    validate_envelope(&request.envelope)?;
    if request.new_token.len() != 43
        || !request
            .new_token
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_'))
    {
        return Err(ApiError::Invalid("invalid_new_token"));
    }
    let expected = parse_revision(&headers)?;
    let serialized = serde_json::to_string(&request.envelope).map_err(|_| ApiError::Internal)?;
    let updated_at = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|_| ApiError::Internal)?
        .as_secs();
    let next_token_hash = token_hash(&request.new_token);

    let mut store = authorize(&headers, &state)?;
    let transaction = store
        .db
        .transaction_with_behavior(TransactionBehavior::Immediate)
        .map_err(|error| {
            warn!(%error, "credential rotation transaction failed");
            ApiError::Internal
        })?;
    let current: u64 = transaction
        .query_row("SELECT revision FROM vault WHERE id = 1", [], |row| {
            row.get(0)
        })
        .optional()
        .map_err(|_| ApiError::Internal)?
        .ok_or(ApiError::Missing)?;
    if current != expected {
        return Err(ApiError::Conflict);
    }
    let revision = current.checked_add(1).ok_or(ApiError::Internal)?;
    transaction
        .execute(
            "UPDATE vault SET revision = ?1, updated_at = ?2, envelope = ?3 WHERE id = 1",
            params![revision, updated_at, serialized],
        )
        .map_err(|error| {
            warn!(%error, "vault credential rotation failed");
            ApiError::Internal
        })?;
    transaction
        .execute(
            "UPDATE sync_settings SET value = ?1 WHERE key = 'token_hash'",
            params![next_token_hash.as_slice()],
        )
        .map_err(|error| {
            warn!(%error, "authentication hash rotation failed");
            ApiError::Internal
        })?;
    transaction.commit().map_err(|_| ApiError::Internal)?;
    store.token_hash = next_token_hash;

    let mut response = (
        StatusCode::OK,
        Json(serde_json::json!({"revision": revision, "updated_at": updated_at})),
    )
        .into_response();
    response.headers_mut().insert(
        header::ETAG,
        HeaderValue::from_str(&format!("\"{revision}\"")).map_err(|_| ApiError::Internal)?,
    );
    response
        .headers_mut()
        .insert(header::CACHE_CONTROL, HeaderValue::from_static("no-store"));
    Ok(response)
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    let listen: SocketAddr = env::var("TOKENPLAN_LISTEN")
        .unwrap_or_else(|_| "127.0.0.1:8787".into())
        .parse()
        .context("parse TOKENPLAN_LISTEN")?;
    let database =
        PathBuf::from(env::var("TOKENPLAN_DATABASE").unwrap_or_else(|_| "tokenplan.db".into()));
    let token = env::var("TOKENPLAN_SYNC_TOKEN").context("TOKENPLAN_SYNC_TOKEN is required")?;
    if token.len() < 32 {
        anyhow::bail!("TOKENPLAN_SYNC_TOKEN must contain at least 32 characters");
    }

    let router = app(initialize_database(&database)?, &token)?;
    let listener = tokio::net::TcpListener::bind(listen).await?;
    info!(%listen, database = %database.display(), "TokenPlan sync API listening");
    axum::serve(listener, router)
        .with_graceful_shutdown(shutdown_signal())
        .await?;
    Ok(())
}

async fn shutdown_signal() {
    let ctrl_c = async {
        tokio::signal::ctrl_c().await.ok();
    };
    #[cfg(unix)]
    let terminate = async {
        tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
            .expect("install SIGTERM handler")
            .recv()
            .await;
    };
    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();
    tokio::select! { _ = ctrl_c => {}, _ = terminate => {} }
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::Body;
    use axum::http::Request;
    use http_body_util::BodyExt;
    use tower::ServiceExt;

    fn test_app() -> Router {
        let connection = Connection::open_in_memory().unwrap();
        initialize_connection(&connection).unwrap();
        app(connection, &"x".repeat(40)).unwrap()
    }

    fn request(method: &str, path: &str, token: bool, revision: Option<u64>) -> Request<Body> {
        let mut builder = Request::builder().method(method).uri(path);
        if token {
            builder = builder.header(header::AUTHORIZATION, format!("Bearer {}", "x".repeat(40)));
        }
        if let Some(revision) = revision {
            builder = builder.header(header::IF_MATCH, format!("\"{revision}\""));
        }
        builder
            .header(header::CONTENT_TYPE, "application/json")
            .body(Body::from(
                r#"{"schema_version":1,"nonce":"fictional-nonce","ciphertext":"opaque-ciphertext"}"#,
            ))
            .unwrap()
    }

    #[tokio::test]
    async fn auth_create_read_and_conflict() {
        let router = test_app();
        let unauthorized = router
            .clone()
            .oneshot(request("GET", "/api/v1/vault", false, None))
            .await
            .unwrap();
        assert_eq!(unauthorized.status(), StatusCode::UNAUTHORIZED);

        let created = router
            .clone()
            .oneshot(request("PUT", "/api/v1/vault", true, Some(0)))
            .await
            .unwrap();
        assert_eq!(created.status(), StatusCode::OK);
        assert_eq!(created.headers()[header::ETAG], "\"1\"");

        let read = router
            .clone()
            .oneshot(request("GET", "/api/v1/vault", true, None))
            .await
            .unwrap();
        assert_eq!(read.status(), StatusCode::OK);
        let body = read.into_body().collect().await.unwrap().to_bytes();
        let value: serde_json::Value = serde_json::from_slice(&body).unwrap();
        assert_eq!(value["revision"], 1);
        assert_eq!(value["envelope"]["ciphertext"], "opaque-ciphertext");

        let conflict = router
            .oneshot(request("PUT", "/api/v1/vault", true, Some(0)))
            .await
            .unwrap();
        assert_eq!(conflict.status(), StatusCode::CONFLICT);
    }

    #[tokio::test]
    async fn credential_rotation_reencrypts_vault_and_revokes_old_token() {
        let router = test_app();
        let created = router
            .clone()
            .oneshot(request("PUT", "/api/v1/vault", true, Some(0)))
            .await
            .unwrap();
        assert_eq!(created.status(), StatusCode::OK);

        let new_token = "y".repeat(43);
        let body = serde_json::json!({
            "new_token": new_token,
            "envelope": {
                "schema_version": 1,
                "nonce": "new-fictional-nonce",
                "ciphertext": "new-opaque-ciphertext"
            }
        });
        let rotated = router
            .clone()
            .oneshot(
                Request::builder()
                    .method("PUT")
                    .uri("/api/v1/vault/credentials")
                    .header(header::AUTHORIZATION, format!("Bearer {}", "x".repeat(40)))
                    .header(header::IF_MATCH, "\"1\"")
                    .header(header::CONTENT_TYPE, "application/json")
                    .body(Body::from(body.to_string()))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(rotated.status(), StatusCode::OK);
        assert_eq!(rotated.headers()[header::ETAG], "\"2\"");

        let old_read = router
            .clone()
            .oneshot(request("GET", "/api/v1/vault", true, None))
            .await
            .unwrap();
        assert_eq!(old_read.status(), StatusCode::UNAUTHORIZED);

        let new_read = router
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/api/v1/vault")
                    .header(header::AUTHORIZATION, format!("Bearer {new_token}"))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(new_read.status(), StatusCode::OK);
        let body = new_read.into_body().collect().await.unwrap().to_bytes();
        let value: serde_json::Value = serde_json::from_slice(&body).unwrap();
        assert_eq!(value["revision"], 2);
        assert_eq!(value["envelope"]["ciphertext"], "new-opaque-ciphertext");
    }

    #[tokio::test]
    async fn health_does_not_require_auth() {
        let response = test_app()
            .oneshot(request("GET", "/healthz", false, None))
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        assert_eq!(response.headers()[header::CACHE_CONTROL], "no-store");
    }
}
