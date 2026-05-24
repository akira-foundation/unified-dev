use akira_billing::Client;

pub const PRODUCT_SLUG: &str = "unified-dev";
pub const DEFAULT_BILLING_URL: &str = "https://billing.test";

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
}

impl BillingClient {
    pub fn from_build_env() -> Self {
        let secret = env!("AKIRA_BILLING_SECRET").to_string();
        Self {
            inner: Client::new(base_url(env!("AKIRA_BILLING_URL")), PRODUCT_SLUG, secret),
            has_customer_token: false,
        }
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
