// Data contract adapted from cc-switch (MIT). See THIRD_PARTY_NOTICES.md.
use serde::{Deserialize, Serialize};

pub const TIER_FIVE_HOUR: &str = "five_hour";
pub const TIER_WEEKLY_LIMIT: &str = "weekly_limit";
pub const TIER_MONTHLY: &str = "monthly";

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CredentialStatus {
    Valid,
    Expired,
    NotFound,
    ParseError,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct QuotaTier {
    pub name: String,
    pub utilization: f64,
    pub resets_at: Option<String>,
    pub used_value_usd: Option<f64>,
    pub max_value_usd: Option<f64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SubscriptionQuota {
    pub tool: String,
    pub credential_status: CredentialStatus,
    pub credential_message: Option<String>,
    pub success: bool,
    pub tiers: Vec<QuotaTier>,
    pub extra_usage: Option<serde_json::Value>,
    pub error: Option<String>,
    pub queried_at: Option<i64>,
}
