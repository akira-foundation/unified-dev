use akira_billing::Client;
use serde::Deserialize;

use crate::app::support::error::{AppError, AppResult};

pub const PRODUCT_SLUG: &str = "unified-dev";
pub const DEFAULT_BILLING_URL: &str = "https://billing.test";

#[derive(Debug, Clone, Deserialize)]
pub struct JiraTokens {
    pub access_token: String,
    #[serde(default)]
    pub refresh_token: Option<String>,
    #[serde(default)]
    pub expires_in: i64,
}

pub fn base_url(raw: &str) -> String {
    if raw.is_empty() {
        DEFAULT_BILLING_URL.to_string()
    } else {
        raw.to_string()
    }
}

#[derive(Debug, Clone)]
pub struct BillingClient {
    inner: Client,
    has_customer_token: bool,
    base_url: String,
    secret: String,
}

impl BillingClient {
    pub fn from_build_env() -> Self {
        let secret = env!("AKIRA_BILLING_SECRET").to_string();
        let url = base_url(env!("AKIRA_BILLING_URL"));
        Self {
            inner: Client::new(url.clone(), PRODUCT_SLUG, secret.clone()),
            has_customer_token: false,
            base_url: url,
            secret,
        }
    }

    pub fn jira_connect_url(&self, redirect_uri: &str, code_challenge: &str, state: &str) -> String {
        let endpoint = format!("{}/integrations/atlassian/connect", self.base_url.trim_end_matches('/'));
        reqwest::Url::parse_with_params(
            &endpoint,
            &[
                ("redirect_uri", redirect_uri),
                ("code_challenge", code_challenge),
                ("code_challenge_method", "S256"),
                ("state", state),
            ],
        )
        .map(|url| url.to_string())
        .unwrap_or(endpoint)
    }

    pub async fn jira_exchange(&self, code: &str, code_verifier: &str) -> AppResult<JiraTokens> {
        let body = serde_json::json!({ "code": code, "code_verifier": code_verifier }).to_string();
        self.signed_post("/api/v1/integrations/atlassian/exchange", &body).await
    }

    pub async fn jira_refresh(&self, refresh_token: &str) -> AppResult<JiraTokens> {
        let body = serde_json::json!({ "refresh_token": refresh_token }).to_string();
        self.signed_post("/api/v1/integrations/atlassian/refresh", &body).await
    }

    async fn signed_post(&self, path: &str, body: &str) -> AppResult<JiraTokens> {
        let url = format!("{}{}", self.base_url.trim_end_matches('/'), path);
        let timestamp = chrono::Utc::now().timestamp();
        let nonce = akira_billing::signature::new_nonce();
        let canonical =
            akira_billing::signature::canonical(PRODUCT_SLUG, timestamp, &nonce, "POST", path, body.as_bytes());
        let signature = akira_billing::signature::sign(&self.secret, &canonical);

        let response = reqwest::Client::new()
            .post(&url)
            .header("X-Akira-Product", PRODUCT_SLUG)
            .header("X-Akira-Timestamp", timestamp.to_string())
            .header("X-Akira-Nonce", nonce)
            .header("X-Akira-Signature", signature)
            .header("Content-Type", "application/json")
            .header("Accept", "application/json")
            .body(body.to_string())
            .send()
            .await
            .map_err(|err| AppError::Provider(format!("billing request failed: {err}")))?;

        let status = response.status();
        if !status.is_success() {
            let text = response.text().await.unwrap_or_default();
            return Err(AppError::Provider(format!("billing {status}: {text}")));
        }

        response
            .json::<JiraTokens>()
            .await
            .map_err(|err| AppError::Provider(format!("billing decode failed: {err}")))
    }

    pub fn inner(&self) -> &Client {
        &self.inner
    }

    pub fn inner_mut(&mut self) -> &mut Client {
        &mut self.inner
    }

    pub fn has_customer_token(&self) -> bool {
        self.has_customer_token
    }

    pub fn set_customer_token(&mut self, token: impl Into<String>) {
        self.inner.set_customer_token(token);
        self.has_customer_token = true;
    }

    pub fn clear_customer_token(&mut self) {
        self.inner.clear_customer_token();
        self.has_customer_token = false;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_env_falls_back_to_https_default() {
        assert_eq!(base_url(""), "https://billing.test");
    }

    #[test]
    fn configured_url_passes_through() {
        assert_eq!(base_url("https://billing.akira-io.com"), "https://billing.akira-io.com");
    }
}
