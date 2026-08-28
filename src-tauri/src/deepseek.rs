//! DeepSeek's official balance API, not a Token Plan quota.
//! https://api-docs.deepseek.com/api/get-user-balance/
use serde::{Deserialize, Serialize};

pub const BASE_URL: &str = "https://api.deepseek.com";

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all(serialize = "camelCase"))]
pub struct Balance {
    pub currency: String,
    pub total_balance: String,
    pub granted_balance: String,
    pub topped_up_balance: String,
}

#[derive(Deserialize)]
struct Response {
    is_available: bool,
    balance_infos: Vec<Balance>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BalanceUsage {
    kind: &'static str,
    success: bool,
    is_available: bool,
    balances: Vec<Balance>,
    queried_at: i64,
}

fn valid_amount(value: &str) -> bool {
    // Retain the API's decimal strings for exact display (no currency conversion).
    let digits = value.strip_prefix('-').unwrap_or(value);
    let mut parts = digits.split('.');
    let integer = parts.next().unwrap_or("");
    let fraction = parts.next();
    !integer.is_empty()
        && integer.bytes().all(|b| b.is_ascii_digit())
        && fraction.is_none_or(|f| !f.is_empty() && f.bytes().all(|b| b.is_ascii_digit()))
        && parts.next().is_none()
        && value.parse::<f64>().is_ok_and(|n| n.is_finite())
}

fn parse_balance(body: &str) -> Result<BalanceUsage, String> {
    const INVALID: &str = "DeepSeek: unrecognized balance response / 无法识别余额数据";
    // Never include the response body or serde error: they may contain credentials.
    let response: Response = serde_json::from_str(body).map_err(|_| INVALID)?;
    let mut currencies = std::collections::HashSet::new();
    if response.balance_infos.is_empty()
        || response.balance_infos.iter().any(|balance| {
            !matches!(balance.currency.as_str(), "CNY" | "USD")
                || !currencies.insert(balance.currency.as_str())
                || [
                    &balance.total_balance,
                    &balance.granted_balance,
                    &balance.topped_up_balance,
                ]
                .iter()
                .any(|value| !valid_amount(value))
        })
    {
        return Err(INVALID.into());
    }
    Ok(BalanceUsage {
        kind: "balance",
        success: true,
        is_available: response.is_available,
        balances: response.balance_infos,
        queried_at: chrono::Utc::now().timestamp_millis(),
    })
}

pub async fn query(api_key: &str) -> Result<BalanceUsage, String> {
    request(&crate::http_client::get(), BASE_URL, api_key).await
}

// Only tests inject a different base; production never accepts a user-supplied URL.
async fn request(
    client: &reqwest::Client,
    base: &str,
    api_key: &str,
) -> Result<BalanceUsage, String> {
    let response = client
        .get(format!("{base}/user/balance"))
        .bearer_auth(api_key)
        .send()
        .await
        .map_err(|_| "DeepSeek: network request failed / 网络请求失败，请检查网络后重试")?;
    if !response.status().is_success() {
        let reason = match response.status().as_u16() {
            401 | 403 => "check your official DeepSeek API key / 请检查 DeepSeek 官方 API Key",
            429 => "rate limited, retry later / 请求过于频繁，请稍后重试",
            _ => "balance request failed / 余额查询失败",
        };
        return Err(format!(
            "DeepSeek HTTP {}: {reason}",
            response.status().as_u16()
        ));
    }
    let body = response
        .text()
        .await
        .map_err(|_| "DeepSeek: failed to read balance response / 无法读取余额响应")?;
    parse_balance(&body)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn fixture(available: bool, total: &str) -> serde_json::Value {
        json!({ "is_available": available, "balance_infos": [{
            "currency": "CNY", "total_balance": total,
            "granted_balance": "10.0000", "topped_up_balance": "100.00"
        }] })
    }

    #[test]
    fn official_response_preserves_decimals_and_serializes_for_frontend() {
        let parsed = parse_balance(&fixture(true, "110.0000").to_string()).unwrap();
        let value = serde_json::to_value(parsed).unwrap();
        assert_eq!(value["kind"], "balance");
        assert_eq!(value["balances"][0]["totalBalance"], "110.0000");
        assert_eq!(value["isAvailable"], true);
        assert!(value["queriedAt"].as_i64().unwrap() > 0);
        assert!(value.get("tiers").is_none());
    }

    #[test]
    fn depleted_balance_is_success_not_an_auth_failure() {
        for total in ["0.00", "-0.01"] {
            let parsed = parse_balance(&fixture(false, total).to_string()).unwrap();
            assert!(parsed.success);
            assert!(!parsed.is_available);
            assert_eq!(parsed.balances[0].total_balance, total);
        }
    }

    #[test]
    fn currencies_stay_separate() {
        let mut body = fixture(true, "110.00");
        let mut usd = body["balance_infos"][0].clone();
        usd["currency"] = json!("USD");
        body["balance_infos"].as_array_mut().unwrap().push(usd);
        let parsed = parse_balance(&body.to_string()).unwrap();
        assert_eq!(parsed.balances.len(), 2);
        assert_eq!(parsed.balances[1].currency, "USD");
    }

    #[test]
    fn malformed_or_missing_amounts_are_not_zero_balances() {
        for invalid in ["NaN", "Infinity", "", " ", "1e5", "1.2.3", ".5", "1."] {
            assert!(parse_balance(&fixture(true, invalid).to_string()).is_err());
        }
        for invalid in [
            json!({}),
            json!({"is_available": true, "balance_infos": []}),
            json!({"is_available": "false", "balance_infos": []}),
        ] {
            assert!(parse_balance(&invalid.to_string()).is_err());
        }
        let mut body = fixture(true, "1");
        body["balance_infos"][0]
            .as_object_mut()
            .unwrap()
            .remove("granted_balance");
        assert!(parse_balance(&body.to_string()).is_err());
        let mut body = fixture(true, "1");
        body["balance_infos"][0]["currency"] = json!("EUR");
        assert!(parse_balance(&body.to_string()).is_err());
        let mut body = fixture(true, "1");
        let duplicate = body["balance_infos"][0].clone();
        body["balance_infos"]
            .as_array_mut()
            .unwrap()
            .push(duplicate);
        assert!(parse_balance(&body.to_string()).is_err());
    }

    async fn mock_request(status: u16, body: String) -> (Result<BalanceUsage, String>, String) {
        use std::io::{Read, Write};
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let base = format!("http://{}", listener.local_addr().unwrap());
        let server = std::thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            stream
                .set_read_timeout(Some(std::time::Duration::from_secs(5)))
                .unwrap();
            let mut incoming = Vec::new();
            let mut chunk = [0u8; 1024];
            while !incoming.windows(4).any(|w| w == b"\r\n\r\n") {
                let n = stream.read(&mut chunk).unwrap();
                assert!(n > 0);
                incoming.extend_from_slice(&chunk[..n]);
            }
            write!(stream, "HTTP/1.1 {status} Test\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}", body.len()).unwrap();
            String::from_utf8(incoming).unwrap()
        });
        let client = reqwest::Client::builder()
            .no_proxy()
            .timeout(std::time::Duration::from_secs(5))
            .redirect(reqwest::redirect::Policy::none())
            .build()
            .unwrap();
        let result = request(&client, &base, "fictional-test-key").await;
        (result, server.join().unwrap())
    }

    #[tokio::test]
    async fn request_uses_get_path_and_bearer_key() {
        let (result, request) = mock_request(200, fixture(true, "110.00").to_string()).await;
        assert!(result.unwrap().success);
        assert!(request.starts_with("GET /user/balance HTTP/1.1"));
        assert!(request
            .to_lowercase()
            .contains("authorization: bearer fictional-test-key\r\n"));
        assert!(!request
            .lines()
            .next()
            .unwrap()
            .contains("fictional-test-key"));
    }

    #[tokio::test]
    async fn http_errors_and_malformed_json_do_not_expose_body() {
        for status in [200, 302, 401, 403, 429, 500] {
            let (result, _) = mock_request(status, "fictional-test-key secret body".into()).await;
            let error = result.unwrap_err();
            assert!(!error.contains("fictional-test-key"));
            assert!(!error.contains("secret body"));
            if status != 200 {
                assert!(error.contains(&status.to_string()));
            }
        }
    }
}
