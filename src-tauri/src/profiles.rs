use serde::{Deserialize, Serialize};

pub const PROVIDERS: &[&str] = &[
    "volcengine",
    "kimi",
    "zhipu",
    "zhipu_team",
    "minimax",
    "zenmux",
    "opencode_go",
    "deepseek",
];

#[derive(Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Profile {
    pub id: String,
    pub name: String,
    pub provider: String,
    // Retained for compatibility with the original encrypted profiles.dat.
    pub r#type: String,
    pub access_key: String,
    pub secret_key: String,
    pub api_key: String,
    pub region: String,
    pub base_url: String,
    pub organization_id: String,
    pub project_id: String,
    pub enabled: bool,
}

impl Default for Profile {
    fn default() -> Self {
        Self {
            id: String::new(),
            name: "Volcengine Coding Plan".into(),
            provider: "volcengine".into(),
            r#type: "auto".into(),
            access_key: String::new(),
            secret_key: String::new(),
            api_key: String::new(),
            region: "cn".into(),
            base_url: String::new(),
            organization_id: String::new(),
            project_id: String::new(),
            enabled: true,
        }
    }
}

impl Profile {
    pub fn endpoint_base(&self) -> Result<String, String> {
        if !matches!(self.region.as_str(), "cn" | "global") {
            return Err("Invalid region / 无效站点".into());
        }
        let base = match self.provider.as_str() {
            "volcengine" => "https://ark.cn-beijing.volces.com/api/coding/v3",
            "kimi" => "https://api.kimi.com/coding/v1",
            "zhipu" if self.region == "global" => "https://api.z.ai/api/coding/paas/v4",
            "zhipu" | "zhipu_team" => "https://open.bigmodel.cn/api/coding/paas/v4",
            "minimax" if self.region == "global" => "https://api.minimax.io/anthropic",
            "minimax" => "https://api.minimaxi.com/anthropic",
            "opencode_go" => "https://opencode.ai/zen/go/v1",
            "deepseek" => crate::deepseek::BASE_URL,
            "zenmux" => {
                let url = reqwest::Url::parse(self.base_url.trim()).map_err(|_| {
                    "ZenMux: fill in a full HTTPS usage URL / 请填写完整 HTTPS 用量查询地址"
                })?;
                let host = url.host_str().unwrap_or("");
                let trusted = ["zenmux.ai", "zenmux.com"]
                    .iter()
                    .any(|domain| host == *domain || host.ends_with(&format!(".{domain}")));
                if url.scheme() != "https"
                    || !trusted
                    || !url.username().is_empty()
                    || url.password().is_some()
                    || url.fragment().is_some()
                    || url.port().is_some_and(|p| p != 443)
                {
                    return Err("ZenMux: use an HTTPS endpoint on zenmux.ai / zenmux.com (no embedded credentials) / 请使用官方 HTTPS 用量地址".into());
                }
                return Ok(url.to_string());
            }
            _ => return Err("Unsupported Token Plan provider / 不支持的套餐供应商".into()),
        };
        Ok(base.into())
    }

    pub fn validate_query(&self) -> Result<(), String> {
        if !self.enabled {
            return Err("Profile is paused / 此配置已暂停".into());
        }
        self.endpoint_base()?;
        if self.provider == "volcengine" {
            if self.access_key.trim().is_empty() || self.secret_key.trim().is_empty() {
                return Err("Volcengine requires account AK/SK / 火山引擎需要账号 AK/SK".into());
            }
        } else if self.api_key.trim().is_empty() {
            return Err("API key is empty / 请填写 API Key".into());
        }
        if self.provider == "zhipu_team"
            && (self.organization_id.trim().is_empty() || self.project_id.trim().is_empty())
        {
            return Err(
                "Zhipu Team requires organization ID + project ID / 智谱团队需要组织和项目 ID"
                    .into(),
            );
        }
        Ok(())
    }

    pub fn redact(&self, message: &str) -> String {
        let mut result = message.to_string();
        for value in [
            &self.access_key,
            &self.secret_key,
            &self.api_key,
            &self.organization_id,
            &self.project_id,
        ] {
            if !value.trim().is_empty() {
                result = result.replace(value.trim(), "[REDACTED]");
            }
        }
        result.chars().take(500).collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn old_profile_is_still_volcengine_with_credentials_unchanged() {
        let p: Profile = serde_json::from_str(r#"{"name":"old","type":"auto","access_key":"test-ak","secret_key":"test-sk","enabled":true}"#).unwrap();
        assert_eq!(p.provider, "volcengine");
        assert_eq!(p.secret_key, "test-sk");
        assert!(p.validate_query().is_ok());
    }
    #[test]
    fn every_provider_has_a_route_and_preserves_credentials_on_roundtrip() {
        for provider in PROVIDERS {
            let p = Profile {
                provider: provider.to_string(),
                api_key: "test-key".into(),
                access_key: "test-ak".into(),
                secret_key: "test-sk".into(),
                organization_id: "test-org".into(),
                project_id: "test-project".into(),
                base_url: "https://api.zenmux.com/v1/usage".into(),
                ..Profile::default()
            };
            assert!(p.validate_query().is_ok(), "{provider}");
            let roundtrip: Profile =
                serde_json::from_str(&serde_json::to_string(&p).unwrap()).unwrap();
            assert_eq!(roundtrip.provider, *provider);
            assert_eq!(roundtrip.api_key, "test-key");
        }
    }
    #[test]
    fn region_routes_and_team_stays_domestic() {
        for (provider, domain) in [
            ("zhipu", "api.z.ai"),
            ("minimax", "api.minimax.io"),
            ("zhipu_team", "open.bigmodel.cn"),
        ] {
            let p = Profile {
                provider: provider.into(),
                region: "global".into(),
                ..Profile::default()
            };
            assert!(p.endpoint_base().unwrap().contains(domain));
        }
    }
    #[test]
    fn zenmux_rejects_misleading_hosts_and_insecure_urls() {
        for url in [
            "http://zenmux.ai/usage",
            "https://evil.test/zenmux",
            "https://zenmux.ai.evil.test/usage",
            "https://user:password@zenmux.ai/usage",
        ] {
            let p = Profile {
                provider: "zenmux".into(),
                base_url: url.into(),
                ..Profile::default()
            };
            assert!(p.endpoint_base().is_err());
        }
    }
    #[test]
    fn errors_do_not_expose_keys() {
        let p = Profile {
            api_key: "secret-fixture".into(),
            ..Profile::default()
        };
        assert_eq!(p.redact("key=secret-fixture"), "key=[REDACTED]");
    }

    #[test]
    fn deepseek_requires_key_and_ignores_custom_endpoint() {
        let mut p = Profile {
            provider: "deepseek".into(),
            base_url: "https://untrusted.example".into(),
            ..Profile::default()
        };
        assert!(p.validate_query().is_err());
        p.api_key = "fictional-deepseek".into();
        assert!(p.validate_query().is_ok());
        assert_eq!(p.endpoint_base().unwrap(), "https://api.deepseek.com");
    }
}
