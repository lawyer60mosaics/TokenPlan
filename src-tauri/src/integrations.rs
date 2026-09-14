use crate::{app_data_dir, protect, replace_file};
use serde::{Deserialize, Serialize};
use std::fs;

#[derive(Clone, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct NotificationSettings {
    pub dingtalk_enabled: bool,
    pub dingtalk_webhook: String,
    pub wecom_enabled: bool,
    pub wecom_webhook: String,
    pub notify_on_success: bool,
    pub notify_on_failure: bool,
}

impl Default for NotificationSettings {
    fn default() -> Self {
        Self {
            dingtalk_enabled: false,
            dingtalk_webhook: String::new(),
            wecom_enabled: false,
            wecom_webhook: String::new(),
            notify_on_success: true,
            notify_on_failure: true,
        }
    }
}

#[derive(Clone, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct CloudSettings {
    pub provider: String,
    pub aliyun_access_key_id: String,
    pub aliyun_access_key_secret: String,
    pub aliyun_account_id: String,
    pub aliyun_region: String,
    pub tencent_secret_id: String,
    pub tencent_secret_key: String,
    pub tencent_region: String,
}

impl Default for CloudSettings {
    fn default() -> Self {
        Self {
            provider: "github".into(),
            aliyun_access_key_id: String::new(),
            aliyun_access_key_secret: String::new(),
            aliyun_account_id: String::new(),
            aliyun_region: "cn-shanghai".into(),
            tencent_secret_id: String::new(),
            tencent_secret_key: String::new(),
            tencent_region: "ap-shanghai".into(),
        }
    }
}

#[derive(Clone, Default, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct IntegrationSettings {
    pub notifications: NotificationSettings,
    pub cloud: CloudSettings,
}

fn path() -> std::path::PathBuf {
    app_data_dir().join("integrations.dat")
}

pub fn load() -> Result<IntegrationSettings, String> {
    if !path().exists() {
        return Ok(IntegrationSettings::default());
    }
    let raw = protect(&fs::read(path()).map_err(|e| e.to_string())?, true)?;
    serde_json::from_slice(&raw).map_err(|_| "集成配置文件无法解析，原文件已保留".into())
}

pub fn save(settings: IntegrationSettings) -> Result<IntegrationSettings, String> {
    validate(&settings)?;
    let destination = path();
    fs::create_dir_all(destination.parent().unwrap()).map_err(|e| e.to_string())?;
    let raw = serde_json::to_vec(&settings).map_err(|e| e.to_string())?;
    let encrypted = protect(&raw, false)?;
    let temporary = destination.with_extension("dat.tmp");
    fs::write(&temporary, encrypted).map_err(|e| e.to_string())?;
    replace_file(&temporary, &destination)?;
    Ok(settings)
}

fn validate(settings: &IntegrationSettings) -> Result<(), String> {
    if !matches!(
        settings.cloud.provider.as_str(),
        "github" | "aliyun" | "tencent"
    ) {
        return Err("请选择有效的云平台".into());
    }
    if settings.notifications.dingtalk_enabled {
        validate_webhook("dingtalk", &settings.notifications.dingtalk_webhook)?;
    }
    if settings.notifications.wecom_enabled {
        validate_webhook("wecom", &settings.notifications.wecom_webhook)?;
    }
    if settings.cloud.provider == "aliyun"
        && [
            &settings.cloud.aliyun_access_key_id,
            &settings.cloud.aliyun_access_key_secret,
            &settings.cloud.aliyun_account_id,
            &settings.cloud.aliyun_region,
        ]
        .iter()
        .any(|value| value.trim().is_empty())
    {
        return Err("请完整填写阿里云 AccessKey、账号 ID 和地域".into());
    }
    if settings.cloud.provider == "tencent"
        && [
            &settings.cloud.tencent_secret_id,
            &settings.cloud.tencent_secret_key,
            &settings.cloud.tencent_region,
        ]
        .iter()
        .any(|value| value.trim().is_empty())
    {
        return Err("请完整填写腾讯云 SecretId、SecretKey 和地域".into());
    }
    Ok(())
}

fn validate_webhook(kind: &str, value: &str) -> Result<reqwest::Url, String> {
    let url =
        reqwest::Url::parse(value.trim()).map_err(|_| "Webhook 地址格式不正确".to_string())?;
    let expected = if kind == "dingtalk" {
        "oapi.dingtalk.com"
    } else {
        "qyapi.weixin.qq.com"
    };
    if url.scheme() != "https"
        || url.host_str() != Some(expected)
        || !url.username().is_empty()
        || url.password().is_some()
    {
        return Err(format!("请使用 {expected} 官方 HTTPS Webhook"));
    }
    Ok(url)
}

pub async fn test_notification(kind: String, webhook: String) -> Result<String, String> {
    let url = validate_webhook(&kind, &webhook)?;
    let body = if kind == "dingtalk" {
        serde_json::json!({"msgtype":"text","text":{"content":"TokenPlan 测试通知：连接成功"}})
    } else if kind == "wecom" {
        serde_json::json!({"msgtype":"text","text":{"content":"TokenPlan 测试通知：连接成功"}})
    } else {
        return Err("不支持的通知类型".into());
    };
    let response = crate::http_client::get()
        .post(url)
        .json(&body)
        .send()
        .await
        .map_err(|e| e.to_string())?;
    let status = response.status();
    let text = response.text().await.map_err(|e| e.to_string())?;
    if !status.is_success() {
        return Err(format!(
            "Webhook HTTP {}: {}",
            status.as_u16(),
            text.chars().take(160).collect::<String>()
        ));
    }
    let result: serde_json::Value = serde_json::from_str(&text).unwrap_or_default();
    let code = result.get("errcode").and_then(|v| v.as_i64()).unwrap_or(-1);
    if code != 0 {
        return Err(format!(
            "机器人返回错误：{}",
            text.chars().take(200).collect::<String>()
        ));
    }
    Ok("测试通知发送成功".into())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn webhooks_only_allow_official_https_hosts() {
        assert!(validate_webhook(
            "dingtalk",
            "https://oapi.dingtalk.com/robot/send?access_token=test"
        )
        .is_ok());
        assert!(validate_webhook(
            "wecom",
            "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=test"
        )
        .is_ok());
        assert!(
            validate_webhook("dingtalk", "https://oapi.dingtalk.com.evil.test/robot/send").is_err()
        );
        assert!(
            validate_webhook("wecom", "http://qyapi.weixin.qq.com/cgi-bin/webhook/send").is_err()
        );
    }
}
