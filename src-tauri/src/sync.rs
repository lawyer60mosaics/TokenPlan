use crate::{profiles::Profile, protect, replace_file, save_profiles_impl, validate_profiles};
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
use chacha20poly1305::{
    aead::{Aead, KeyInit, Payload},
    XChaCha20Poly1305, XNonce,
};
use reqwest::{header, redirect::Policy, StatusCode, Url};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{fs, path::PathBuf, time::Duration};

const ENDPOINT: &str = "https://47.102.119.11";
const SCHEMA_VERSION: u32 = 2;
const AAD: &[u8] = b"tokenplan-vault-v2";

#[derive(Clone, Serialize, Deserialize)]
struct SyncConfig {
    enabled: bool,
    username: String,
    password: String,
    revision: u64,
}

#[derive(Deserialize)]
struct LegacySyncConfig {
    endpoint: String,
    token: String,
    vault_key: String,
}

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncState {
    enabled: bool,
    username: String,
    revision: u64,
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
            username: config.username.clone(),
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
    let config: SyncConfig = match serde_json::from_slice(&decrypted) {
        Ok(config) => config,
        Err(_) => {
            if let Ok(legacy) = serde_json::from_slice::<LegacySyncConfig>(&decrypted) {
                let _ = (legacy.endpoint, legacy.token, legacy.vault_key);
                return Ok(None);
            }
            return Err("Invalid sync configuration / 云同步配置无法解析".into());
        }
    };
    validate_credentials(&config.username, &config.password)?;
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

fn validate_credentials(username: &str, password: &str) -> Result<(), String> {
    let username_valid = (3..=64).contains(&username.len())
        && username
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || b"._-@".contains(&byte));
    if !username_valid {
        return Err("Account must use 3-64 letters, numbers, . _ - @ / 账号格式无效".into());
    }
    if !(16..=128).contains(&password.len()) {
        return Err("Password must contain 16-128 characters / 密码至少需要 16 个字符".into());
    }
    Ok(())
}

fn derive(domain: &[u8], username: &str, password: &str) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(domain);
    hasher.update([0]);
    hasher.update(username.as_bytes());
    hasher.update([0]);
    hasher.update(password.as_bytes());
    hasher.finalize().into()
}

fn auth_token(config: &SyncConfig) -> String {
    URL_SAFE_NO_PAD.encode(derive(
        b"tokenplan-auth-v2",
        &config.username,
        &config.password,
    ))
}

fn vault_key(config: &SyncConfig) -> [u8; 32] {
    derive(b"tokenplan-vault-v2", &config.username, &config.password)
}

fn vault_url() -> Result<Url, String> {
    let mut url =
        Url::parse(ENDPOINT).map_err(|_| "Invalid sync endpoint / 云同步地址无效".to_string())?;
    if url.scheme() != "https"
        || url.host_str().is_none()
        || !url.username().is_empty()
        || url.password().is_some()
        || url.query().is_some()
        || url.fragment().is_some()
        || !matches!(url.path(), "" | "/")
        || url.port().is_some_and(|port| port != 443)
    {
        return Err("Built-in sync endpoint is invalid / 内置同步地址无效".into());
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
        .map_err(|_| "Cannot decrypt cloud profiles; check account and password / 无法解密云端配置，请检查账号密码".into())
}

pub fn state() -> Result<Option<SyncState>, String> {
    Ok(load_config()?.as_ref().map(SyncState::from))
}

pub fn configure(username: String, password: String) -> Result<SyncState, String> {
    vault_url()?;
    let username = username.trim().to_string();
    validate_credentials(&username, &password)?;
    let existing = load_config()?;
    let revision = existing
        .as_ref()
        .filter(|config| config.username == username && config.password == password)
        .map_or(0, |config| config.revision);
    let config = SyncConfig {
        enabled: true,
        username,
        password,
        revision,
    };
    save_config(&config)?;
    Ok(SyncState::from(&config))
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
    let key = vault_key(&config);
    let plaintext = serde_json::to_vec(&profiles).map_err(|e| e.to_string())?;
    let envelope = encrypt(&key, &plaintext)?;
    let response = client()?
        .put(vault_url()?)
        .bearer_auth(auth_token(&config))
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
        return Err("Cloud account or password was rejected / 云同步账号或密码错误".into());
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
        .get(vault_url()?)
        .bearer_auth(auth_token(&config))
        .send()
        .await
        .map_err(|_| "Cloud sync request failed / 云同步请求失败")?;
    if response.status() == StatusCode::NOT_FOUND {
        return Err("Cloud vault is empty / 云端尚无配置".into());
    }
    if response.status() == StatusCode::UNAUTHORIZED {
        return Err("Cloud account or password was rejected / 云同步账号或密码错误".into());
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
    let plaintext = decrypt(&vault_key(&config), &vault.envelope)?;
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
    fn built_in_endpoint_and_credentials_are_validated() {
        assert_eq!(
            vault_url().unwrap().as_str(),
            "https://47.102.119.11/api/v1/vault"
        );
        assert!(validate_credentials("tokenplan", "1234567890abcdef").is_ok());
        assert!(validate_credentials("bad account", "1234567890abcdef").is_err());
        assert!(validate_credentials("tokenplan", "short").is_err());
    }

    #[test]
    fn account_password_derives_separate_auth_and_vault_keys() {
        let config = SyncConfig {
            enabled: true,
            username: "tokenplan".into(),
            password: "correct-horse-1234".into(),
            revision: 0,
        };
        assert_eq!(
            auth_token(&config),
            "oNgFfFG1T4-ATA1kPkTCHqMSqXyDfZraNWRv4l0vNBY"
        );
        assert_eq!(
            URL_SAFE_NO_PAD.encode(vault_key(&config)),
            "KP7wj6TG07KvuvKeUYT1mdQY4L361j-GJxg5V3Iu0Sk"
        );
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
            "5QnA4xiIQ0CSe3BIHQFiyQbR1uopPvaE368ifrVPMC_rRS66vqnICUBFvZYuG0oyxMEcQJnVQxo"
        );
    }
}
