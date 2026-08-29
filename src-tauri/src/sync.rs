use crate::{profiles::Profile, protect, replace_file, save_profiles_impl, validate_profiles};
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
use chacha20poly1305::{
    aead::{Aead, KeyInit, Payload},
    XChaCha20Poly1305, XNonce,
};
use reqwest::{header, redirect::Policy, StatusCode, Url};
use serde::{Deserialize, Serialize};
use std::{fs, path::PathBuf, time::Duration};

const SCHEMA_VERSION: u32 = 1;
const AAD: &[u8] = b"tokenplan-vault-v1";

#[derive(Clone, Serialize, Deserialize)]
struct SyncConfig {
    enabled: bool,
    endpoint: String,
    token: String,
    vault_key: String,
    revision: u64,
}

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncState {
    enabled: bool,
    endpoint: String,
    revision: u64,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ConfigureResult {
    state: SyncState,
    recovery_key: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PullResult {
    state: SyncState,
    profiles: Vec<Profile>,
}

#[derive(Serialize, Deserialize)]
struct VaultEnvelope {
    schema_version: u32,
    nonce: String,
    ciphertext: String,
}

#[derive(Deserialize)]
struct VaultResponse {
    revision: u64,
    envelope: VaultEnvelope,
}

#[derive(Deserialize)]
struct UpdateResponse {
    revision: u64,
}

impl From<&SyncConfig> for SyncState {
    fn from(config: &SyncConfig) -> Self {
        Self {
            enabled: config.enabled,
            endpoint: config.endpoint.clone(),
            revision: config.revision,
        }
    }
}

fn config_path() -> PathBuf {
    crate::app_data_dir().join("sync.dat")
}

fn load_config() -> Result<Option<SyncConfig>, String> {
    let path = config_path();
    if !path.exists() {
        return Ok(None);
    }
    let decrypted = protect(&fs::read(path).map_err(|e| e.to_string())?, true)?;
    let config: SyncConfig = serde_json::from_slice(&decrypted)
        .map_err(|_| "Invalid sync configuration / 云同步配置无法解析".to_string())?;
    validate_endpoint(&config.endpoint)?;
    if config.token.len() < 32 {
        return Err("Invalid sync token / 云同步令牌无效".into());
    }
    decode_key(&config.vault_key)?;
    Ok(Some(config))
}

fn save_config(config: &SyncConfig) -> Result<(), String> {
    let path = config_path();
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    let serialized = serde_json::to_vec(config).map_err(|e| e.to_string())?;
    let encrypted = protect(&serialized, false)?;
    if path.exists() {
        fs::copy(&path, path.with_extension("dat.bak")).map_err(|e| e.to_string())?;
    }
    let temporary = path.with_extension("dat.tmp");
    fs::write(&temporary, encrypted).map_err(|e| e.to_string())?;
    replace_file(&temporary, &path)
}

fn decode_key(value: &str) -> Result<[u8; 32], String> {
    let bytes = URL_SAFE_NO_PAD
        .decode(value.trim())
        .map_err(|_| "Invalid recovery key / 恢复密钥无效".to_string())?;
    bytes
        .try_into()
        .map_err(|_| "Invalid recovery key / 恢复密钥无效".to_string())
}

fn generate_key() -> Result<String, String> {
    let mut bytes = [0_u8; 32];
    getrandom::fill(&mut bytes).map_err(|_| "Cannot generate recovery key / 无法生成恢复密钥")?;
    Ok(URL_SAFE_NO_PAD.encode(bytes))
}

fn validate_endpoint(endpoint: &str) -> Result<Url, String> {
    let mut url = Url::parse(endpoint.trim())
        .map_err(|_| "Invalid sync endpoint / 云同步地址无效".to_string())?;
    if url.scheme() != "https"
        || url.host_str().is_none()
        || !url.username().is_empty()
        || url.password().is_some()
        || url.query().is_some()
        || url.fragment().is_some()
        || !matches!(url.path(), "" | "/")
        || url.port().is_some_and(|port| port != 443)
    {
        return Err("Sync endpoint must be an HTTPS origin / 云同步地址必须是 HTTPS 根地址".into());
    }
    url.set_path("/api/v1/vault");
    Ok(url)
}

fn client() -> Result<reqwest::Client, String> {
    reqwest::Client::builder()
        .redirect(Policy::none())
        .connect_timeout(Duration::from_secs(5))
        .timeout(Duration::from_secs(15))
        .build()
        .map_err(|_| "Cannot create sync client / 无法创建同步客户端".into())
}

fn encrypt(key: &[u8; 32], plaintext: &[u8]) -> Result<VaultEnvelope, String> {
    let cipher = XChaCha20Poly1305::new_from_slice(key)
        .map_err(|_| "Cannot initialize vault encryption / 无法初始化同步加密")?;
    let mut nonce = [0_u8; 24];
    getrandom::fill(&mut nonce).map_err(|_| "Cannot generate vault nonce / 无法生成加密随机数")?;
    let ciphertext = cipher
        .encrypt(
            XNonce::from_slice(&nonce),
            Payload {
                msg: plaintext,
                aad: AAD,
            },
        )
        .map_err(|_| "Cannot encrypt profiles / 无法加密套餐配置")?;
    Ok(VaultEnvelope {
        schema_version: SCHEMA_VERSION,
        nonce: URL_SAFE_NO_PAD.encode(nonce),
        ciphertext: URL_SAFE_NO_PAD.encode(ciphertext),
    })
}

fn decrypt(key: &[u8; 32], envelope: &VaultEnvelope) -> Result<Vec<u8>, String> {
    if envelope.schema_version != SCHEMA_VERSION {
        return Err("Unsupported cloud vault version / 不支持的云端配置版本".into());
    }
    let nonce = URL_SAFE_NO_PAD
        .decode(&envelope.nonce)
        .map_err(|_| "Invalid cloud vault nonce / 云端随机数无效")?;
    let nonce: [u8; 24] = nonce
        .try_into()
        .map_err(|_| "Invalid cloud vault nonce / 云端随机数无效")?;
    let ciphertext = URL_SAFE_NO_PAD
        .decode(&envelope.ciphertext)
        .map_err(|_| "Invalid cloud vault ciphertext / 云端密文无效")?;
    XChaCha20Poly1305::new_from_slice(key)
        .map_err(|_| "Cannot initialize vault encryption / 无法初始化同步加密")?
        .decrypt(
            XNonce::from_slice(&nonce),
            Payload {
                msg: &ciphertext,
                aad: AAD,
            },
        )
        .map_err(|_| "Cannot decrypt cloud profiles; check the recovery key / 无法解密云端配置，请检查恢复密钥".into())
}

pub fn state() -> Result<Option<SyncState>, String> {
    Ok(load_config()?.as_ref().map(SyncState::from))
}

pub fn configure(
    endpoint: String,
    token: String,
    recovery_key: Option<String>,
) -> Result<ConfigureResult, String> {
    let endpoint = endpoint.trim().trim_end_matches('/').to_string();
    validate_endpoint(&endpoint)?;
    let token = token.trim().to_string();
    if token.len() < 32 {
        return Err(
            "Sync token must contain at least 32 characters / 云同步令牌至少需要 32 个字符".into(),
        );
    }
    let existing = load_config()?;
    let supplied_key = recovery_key.unwrap_or_default().trim().to_string();
    let (vault_key, revision) = if supplied_key.is_empty() {
        existing
            .as_ref()
            .map(|config| (config.vault_key.clone(), config.revision))
            .unwrap_or((generate_key()?, 0))
    } else {
        decode_key(&supplied_key)?;
        (supplied_key, 0)
    };
    let config = SyncConfig {
        enabled: true,
        endpoint,
        token,
        vault_key: vault_key.clone(),
        revision,
    };
    save_config(&config)?;
    Ok(ConfigureResult {
        state: SyncState::from(&config),
        recovery_key: vault_key,
    })
}

pub fn disable() -> Result<(), String> {
    let path = config_path();
    for candidate in [path.clone(), path.with_extension("dat.bak")] {
        match fs::remove_file(candidate) {
            Ok(()) => {}
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
            Err(error) => return Err(error.to_string()),
        }
    }
    Ok(())
}

pub async fn push(profiles: Vec<Profile>) -> Result<SyncState, String> {
    validate_profiles(&profiles)?;
    let mut config = load_config()?.ok_or("Cloud sync is not configured / 尚未配置云同步")?;
    if !config.enabled {
        return Err("Cloud sync is disabled / 云同步已关闭".into());
    }
    let key = decode_key(&config.vault_key)?;
    let plaintext = serde_json::to_vec(&profiles).map_err(|e| e.to_string())?;
    let envelope = encrypt(&key, &plaintext)?;
    let response = client()?
        .put(validate_endpoint(&config.endpoint)?)
        .bearer_auth(&config.token)
        .header(header::IF_MATCH, format!("\"{}\"", config.revision))
        .json(&envelope)
        .send()
        .await
        .map_err(|_| "Cloud sync request failed / 云同步请求失败")?;
    if response.status() == StatusCode::CONFLICT {
        return Err(
            "Cloud version changed; download before uploading / 云端版本已变化，请先下载".into(),
        );
    }
    if response.status() == StatusCode::UNAUTHORIZED {
        return Err("Cloud sync token was rejected / 云同步令牌被拒绝".into());
    }
    if !response.status().is_success() {
        return Err(format!(
            "Cloud upload failed (HTTP {}) / 云端上传失败",
            response.status().as_u16()
        ));
    }
    let update: UpdateResponse = response
        .json()
        .await
        .map_err(|_| "Invalid cloud response / 云端响应无效")?;
    config.revision = update.revision;
    save_config(&config)?;
    Ok(SyncState::from(&config))
}

pub async fn pull() -> Result<PullResult, String> {
    let mut config = load_config()?.ok_or("Cloud sync is not configured / 尚未配置云同步")?;
    let response = client()?
        .get(validate_endpoint(&config.endpoint)?)
        .bearer_auth(&config.token)
        .send()
        .await
        .map_err(|_| "Cloud sync request failed / 云同步请求失败")?;
    if response.status() == StatusCode::NOT_FOUND {
        return Err("Cloud vault is empty / 云端尚无配置".into());
    }
    if response.status() == StatusCode::UNAUTHORIZED {
        return Err("Cloud sync token was rejected / 云同步令牌被拒绝".into());
    }
    if !response.status().is_success() {
        return Err(format!(
            "Cloud download failed (HTTP {}) / 云端下载失败",
            response.status().as_u16()
        ));
    }
    let vault: VaultResponse = response
        .json()
        .await
        .map_err(|_| "Invalid cloud response / 云端响应无效")?;
    let plaintext = decrypt(&decode_key(&config.vault_key)?, &vault.envelope)?;
    let profiles: Vec<Profile> = serde_json::from_slice(&plaintext)
        .map_err(|_| "Invalid profiles in cloud vault / 云端套餐配置无效")?;
    validate_profiles(&profiles)?;
    save_profiles_impl(profiles.clone())?;
    config.revision = vault.revision;
    save_config(&config)?;
    Ok(PullResult {
        state: SyncState::from(&config),
        profiles,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn vault_encryption_roundtrip_and_wrong_key_fails() {
        let key = [7_u8; 32];
        let envelope = encrypt(&key, br#"[{"api_key":"fictional"}]"#).unwrap();
        assert!(!envelope.ciphertext.contains("fictional"));
        assert_eq!(
            decrypt(&key, &envelope).unwrap(),
            br#"[{"api_key":"fictional"}]"#
        );
        assert!(decrypt(&[8_u8; 32], &envelope).is_err());
    }

    #[test]
    fn sync_endpoint_requires_clean_https_origin() {
        assert!(validate_endpoint("https://47.102.119.11").is_ok());
        for endpoint in [
            "http://47.102.119.11",
            "https://user:pass@47.102.119.11",
            "https://47.102.119.11/path",
            "https://47.102.119.11?token=bad",
        ] {
            assert!(validate_endpoint(endpoint).is_err(), "{endpoint}");
        }
    }

    #[test]
    fn ios_compatibility_vector_stays_stable() {
        let key = [7_u8; 32];
        let nonce = [9_u8; 24];
        let ciphertext = XChaCha20Poly1305::new_from_slice(&key)
            .unwrap()
            .encrypt(
                XNonce::from_slice(&nonce),
                Payload {
                    msg: br#"[{"id":"fixture","api_key":"fictional"}]"#,
                    aad: AAD,
                },
            )
            .unwrap();
        assert_eq!(
            URL_SAFE_NO_PAD.encode(ciphertext),
            "5QnA4xiIQ0CSe3BIHQFiyQbR1uopPvaE368ifrVPMC_rRS66vqnICfd2XXcCwjHCI4RTXMIszKE"
        );
    }
}
