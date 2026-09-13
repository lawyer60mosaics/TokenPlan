use anyhow::{Context, Result};
use axum::{
    extract::{DefaultBodyLimit, State},
    http::{header, HeaderMap, HeaderValue, StatusCode},
    response::{IntoResponse, Response},
    routing::get,
    Json, Router,
};
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
use chacha20poly1305::{aead::Aead, KeyInit, XChaCha20Poly1305, XNonce};
use chrono::{Datelike, FixedOffset, Timelike, Utc, Weekday};
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
const PREWARM_URL: &str = "https://ark.cn-beijing.volces.com/api/coding/v3/chat/completions";
const PREWARM_SCHEDULE: &str = "工作日 08:00、13:00";
const PREWARM_TIMEZONE: &str = "Asia/Shanghai";
const PREWARM_MODELS: &[&str] = &[
    "ark-code-latest",
    "doubao-seed-2.0-code",
    "doubao-seed-2.0-pro",
    "doubao-seed-2.0-lite",
    "doubao-seed-code",
    "minimax-m2.5",
    "glm-4.7",
    "deepseek-v3.2",
    "kimi-k2.5",
];

#[derive(Clone)]
struct AppState {
    store: Arc<Mutex<Store>>,
    prewarm_key: [u8; 32],
    client: reqwest::Client,
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

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct PrewarmConfigRequest {
    enabled: bool,
    api_key: Option<String>,
    model: String,
}

#[derive(Clone, Serialize)]
struct PrewarmRun {
    id: u64,
    triggered_at: u64,
    source: String,
    success: bool,
    http_status: Option<u16>,
    error: Option<String>,
}

#[derive(Serialize)]
struct PrewarmConfigResponse {
    enabled: bool,
    model: String,
    schedule: &'static str,
    timezone: &'static str,
    has_api_key: bool,
    last_run: Option<PrewarmRun>,
}

#[derive(Clone)]
struct StoredPrewarmConfig {
    enabled: bool,
    api_key: String,
    model: String,
}

#[derive(Debug)]
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
         );
         CREATE TABLE IF NOT EXISTS prewarm_config (
             id INTEGER PRIMARY KEY CHECK (id = 1),
             enabled INTEGER NOT NULL,
             model TEXT NOT NULL,
             api_key_ciphertext TEXT NOT NULL,
             updated_at INTEGER NOT NULL
         );
         CREATE TABLE IF NOT EXISTS prewarm_runs (
             id INTEGER PRIMARY KEY AUTOINCREMENT,
             slot_key TEXT UNIQUE,
             triggered_at INTEGER NOT NULL,
             source TEXT NOT NULL,
             success INTEGER NOT NULL,
             http_status INTEGER,
             error TEXT
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
        prewarm_key: Sha256::digest(
            [b"tokenplan-prewarm-v1\0".as_slice(), token.as_bytes()].concat(),
        )
        .into(),
        client: reqwest::Client::builder()
            .connect_timeout(std::time::Duration::from_secs(5))
            .timeout(std::time::Duration::from_secs(30))
            .redirect(reqwest::redirect::Policy::none())
            .build()?,
    };
    let router = Router::new()
        .route("/healthz", get(health))
        .route("/api/v1/vault", get(get_vault).put(put_vault))
        .route(
            "/api/v1/vault/credentials",
            axum::routing::put(rotate_credentials),
        )
        .route("/api/v1/prewarm", get(get_prewarm).put(put_prewarm))
        .route("/api/v1/prewarm/run", axum::routing::post(run_prewarm))
        .layer(DefaultBodyLimit::max(256 * 1024))
        .with_state(state.clone());
    tokio::spawn(prewarm_scheduler(state));
    Ok(router)
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

fn encrypt_prewarm_key(key: &[u8; 32], value: &str) -> Result<String, ApiError> {
    let mut nonce = [0_u8; 24];
    getrandom::fill(&mut nonce).map_err(|_| ApiError::Internal)?;
    let ciphertext = XChaCha20Poly1305::new_from_slice(key)
        .map_err(|_| ApiError::Internal)?
        .encrypt(XNonce::from_slice(&nonce), value.as_bytes())
        .map_err(|_| ApiError::Internal)?;
    Ok(format!(
        "{}.{}",
        URL_SAFE_NO_PAD.encode(nonce),
        URL_SAFE_NO_PAD.encode(ciphertext)
    ))
}

fn decrypt_prewarm_key(key: &[u8; 32], value: &str) -> Result<String, ApiError> {
    let (nonce, ciphertext) = value.split_once('.').ok_or(ApiError::Internal)?;
    let nonce: [u8; 24] = URL_SAFE_NO_PAD
        .decode(nonce)
        .map_err(|_| ApiError::Internal)?
        .try_into()
        .map_err(|_| ApiError::Internal)?;
    let ciphertext = URL_SAFE_NO_PAD
        .decode(ciphertext)
        .map_err(|_| ApiError::Internal)?;
    let plaintext = XChaCha20Poly1305::new_from_slice(key)
        .map_err(|_| ApiError::Internal)?
        .decrypt(XNonce::from_slice(&nonce), ciphertext.as_ref())
        .map_err(|_| ApiError::Internal)?;
    String::from_utf8(plaintext).map_err(|_| ApiError::Internal)
}

fn validate_prewarm_model(model: &str) -> Result<(), ApiError> {
    if PREWARM_MODELS.contains(&model) {
        Ok(())
    } else {
        Err(ApiError::Invalid("invalid_prewarm_model"))
    }
}

fn load_prewarm(state: &AppState) -> Result<Option<StoredPrewarmConfig>, ApiError> {
    let store = state.store.lock().map_err(|_| ApiError::Internal)?;
    let row: Option<(bool, String, String)> = store
        .db
        .query_row(
            "SELECT enabled, model, api_key_ciphertext FROM prewarm_config WHERE id = 1",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .optional()
        .map_err(|_| ApiError::Internal)?;
    drop(store);
    row.map(|(enabled, model, ciphertext)| {
        Ok(StoredPrewarmConfig {
            enabled,
            model,
            api_key: decrypt_prewarm_key(&state.prewarm_key, &ciphertext)?,
        })
    })
    .transpose()
}

fn last_prewarm_run(store: &Store) -> Result<Option<PrewarmRun>, ApiError> {
    store
        .db
        .query_row(
            "SELECT id, triggered_at, source, success, http_status, error
             FROM prewarm_runs ORDER BY id DESC LIMIT 1",
            [],
            |row| {
                Ok(PrewarmRun {
                    id: row.get(0)?,
                    triggered_at: row.get(1)?,
                    source: row.get(2)?,
                    success: row.get(3)?,
                    http_status: row.get(4)?,
                    error: row.get(5)?,
                })
            },
        )
        .optional()
        .map_err(|_| ApiError::Internal)
}

async fn get_prewarm(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<Response, ApiError> {
    let store = authorize(&headers, &state)?;
    let row: Option<(bool, String, String)> = store
        .db
        .query_row(
            "SELECT enabled, model, api_key_ciphertext FROM prewarm_config WHERE id = 1",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .optional()
        .map_err(|_| ApiError::Internal)?;
    let last_run = last_prewarm_run(&store)?;
    let (enabled, model, has_api_key) = row
        .map(|(enabled, model, ciphertext)| (enabled, model, !ciphertext.is_empty()))
        .unwrap_or_else(|| (false, "ark-code-latest".into(), false));
    Ok((
        [(header::CACHE_CONTROL, "no-store")],
        Json(PrewarmConfigResponse {
            enabled,
            model,
            schedule: PREWARM_SCHEDULE,
            timezone: PREWARM_TIMEZONE,
            has_api_key,
            last_run,
        }),
    )
        .into_response())
}

async fn put_prewarm(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(request): Json<PrewarmConfigRequest>,
) -> Result<Response, ApiError> {
    validate_prewarm_model(request.model.trim())?;
    let supplied_key = request.api_key.as_deref().map(str::trim);
    if supplied_key.is_some_and(|key| !(8..=512).contains(&key.len())) {
        return Err(ApiError::Invalid("invalid_prewarm_api_key"));
    }
    let store = authorize(&headers, &state)?;
    let existing: Option<String> = store
        .db
        .query_row(
            "SELECT api_key_ciphertext FROM prewarm_config WHERE id = 1",
            [],
            |row| row.get(0),
        )
        .optional()
        .map_err(|_| ApiError::Internal)?;
    let ciphertext = match supplied_key {
        Some(key) => encrypt_prewarm_key(&state.prewarm_key, key)?,
        None => existing.unwrap_or_default(),
    };
    if request.enabled && ciphertext.is_empty() {
        return Err(ApiError::Invalid("prewarm_api_key_required"));
    }
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|_| ApiError::Internal)?
        .as_secs();
    store
        .db
        .execute(
            "INSERT INTO prewarm_config (id, enabled, model, api_key_ciphertext, updated_at)
             VALUES (1, ?1, ?2, ?3, ?4)
             ON CONFLICT(id) DO UPDATE SET enabled = excluded.enabled, model = excluded.model,
               api_key_ciphertext = excluded.api_key_ciphertext, updated_at = excluded.updated_at",
            params![request.enabled, request.model.trim(), ciphertext, now],
        )
        .map_err(|_| ApiError::Internal)?;
    let last_run = last_prewarm_run(&store)?;
    drop(store);
    Ok((
        [(header::CACHE_CONTROL, "no-store")],
        Json(PrewarmConfigResponse {
            enabled: request.enabled,
            model: request.model.trim().into(),
            schedule: PREWARM_SCHEDULE,
            timezone: PREWARM_TIMEZONE,
            has_api_key: !ciphertext.is_empty(),
            last_run,
        }),
    )
        .into_response())
}

async fn perform_prewarm(
    state: &AppState,
    config: StoredPrewarmConfig,
    source: &str,
    reserved_id: Option<u64>,
) -> Result<PrewarmRun, ApiError> {
    let triggered_at = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|_| ApiError::Internal)?
        .as_secs();
    let response = state
        .client
        .post(PREWARM_URL)
        .bearer_auth(&config.api_key)
        .json(&serde_json::json!({
            "model": config.model,
            "messages": [{"role": "user", "content": "Reply with OK."}],
            "max_tokens": 1,
            "stream": false
        }))
        .send()
        .await;
    let (success, http_status, error) = match response {
        Ok(response) if response.status().is_success() => {
            (true, Some(response.status().as_u16()), None)
        }
        Ok(response) => {
            let status = response.status().as_u16();
            let detail = response.text().await.unwrap_or_default();
            let compact: String = detail
                .chars()
                .filter(|c| !c.is_control())
                .take(300)
                .collect();
            (
                false,
                Some(status),
                Some(format!("HTTP {status}: {compact}")),
            )
        }
        Err(error) => (
            false,
            None,
            Some(format!("request_failed: {}", error.without_url())),
        ),
    };
    let store = state.store.lock().map_err(|_| ApiError::Internal)?;
    let id = if let Some(id) = reserved_id {
        store
            .db
            .execute(
                "UPDATE prewarm_runs SET triggered_at = ?1, success = ?2, http_status = ?3, error = ?4 WHERE id = ?5",
                params![triggered_at, success, http_status, error, id],
            )
            .map_err(|_| ApiError::Internal)?;
        id
    } else {
        store
            .db
            .execute(
                "INSERT INTO prewarm_runs (triggered_at, source, success, http_status, error)
                 VALUES (?1, ?2, ?3, ?4, ?5)",
                params![triggered_at, source, success, http_status, error],
            )
            .map_err(|_| ApiError::Internal)?;
        store.db.last_insert_rowid() as u64
    };
    Ok(PrewarmRun {
        id,
        triggered_at,
        source: source.into(),
        success,
        http_status,
        error,
    })
}

async fn run_prewarm(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<Response, ApiError> {
    drop(authorize(&headers, &state)?);
    let config = load_prewarm(&state)?.ok_or(ApiError::Missing)?;
    let result = perform_prewarm(&state, config, "manual", None).await?;
    Ok(([(header::CACHE_CONTROL, "no-store")], Json(result)).into_response())
}

async fn prewarm_scheduler(state: AppState) {
    let mut timer = tokio::time::interval(std::time::Duration::from_secs(30));
    loop {
        timer.tick().await;
        if let Err(error) = run_scheduled_prewarm(&state).await {
            warn!(error = %error.into_response().status(), "prewarm scheduler check failed");
        }
    }
}

async fn run_scheduled_prewarm(state: &AppState) -> Result<(), ApiError> {
    let local = Utc::now().with_timezone(&FixedOffset::east_opt(8 * 3600).unwrap());
    if matches!(local.weekday(), Weekday::Sat | Weekday::Sun) || local.minute() > 30 {
        return Ok(());
    }
    let hour = local.hour();
    if hour != 8 && hour != 13 {
        return Ok(());
    }
    let config = match load_prewarm(state)? {
        Some(config) if config.enabled => config,
        _ => return Ok(()),
    };
    let slot = format!("{}-{hour:02}", local.format("%Y-%m-%d"));
    let id = {
        let store = state.store.lock().map_err(|_| ApiError::Internal)?;
        match store.db.execute(
            "INSERT INTO prewarm_runs (slot_key, triggered_at, source, success, error)
             VALUES (?1, ?2, 'schedule', 0, 'running')",
            params![slot, local.timestamp() as u64],
        ) {
            Ok(_) => store.db.last_insert_rowid() as u64,
            Err(error)
                if error.sqlite_error_code() == Some(rusqlite::ErrorCode::ConstraintViolation) =>
            {
                return Ok(())
            }
            Err(_) => return Err(ApiError::Internal),
        }
    };
    let result = perform_prewarm(state, config, "schedule", Some(id)).await?;
    info!(success = result.success, http_status = ?result.http_status, "scheduled prewarm completed");
    Ok(())
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

    #[test]
    fn prewarm_api_key_encryption_roundtrips_without_plaintext() {
        let key = [7_u8; 32];
        let encrypted = encrypt_prewarm_key(&key, "fictional-coding-key").unwrap();
        assert!(!encrypted.contains("fictional-coding-key"));
        assert_eq!(
            decrypt_prewarm_key(&key, &encrypted).unwrap(),
            "fictional-coding-key"
        );
        assert!(decrypt_prewarm_key(&[8_u8; 32], &encrypted).is_err());
    }

    #[tokio::test]
    async fn prewarm_configuration_never_returns_api_key() {
        let router = test_app();
        let body = serde_json::json!({
            "enabled": true,
            "api_key": "fictional-coding-key",
            "model": "ark-code-latest"
        });
        let saved = router
            .clone()
            .oneshot(
                Request::builder()
                    .method("PUT")
                    .uri("/api/v1/prewarm")
                    .header(header::AUTHORIZATION, format!("Bearer {}", "x".repeat(40)))
                    .header(header::CONTENT_TYPE, "application/json")
                    .body(Body::from(body.to_string()))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(saved.status(), StatusCode::OK);
        let body = saved.into_body().collect().await.unwrap().to_bytes();
        let text = String::from_utf8(body.to_vec()).unwrap();
        assert!(!text.contains("fictional-coding-key"));
        let value: serde_json::Value = serde_json::from_str(&text).unwrap();
        assert_eq!(value["has_api_key"], true);
        assert_eq!(value["schedule"], PREWARM_SCHEDULE);

        let read = router
            .oneshot(request("GET", "/api/v1/prewarm", true, None))
            .await
            .unwrap();
        assert_eq!(read.status(), StatusCode::OK);
        let body = read.into_body().collect().await.unwrap().to_bytes();
        assert!(!String::from_utf8(body.to_vec())
            .unwrap()
            .contains("fictional-coding-key"));
    }
}
