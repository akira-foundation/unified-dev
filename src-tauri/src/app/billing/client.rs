use akira_billing::Client;

pub const PRODUCT_SLUG: &str = "unified-dev";

#[derive(Debug, Clone)]
pub struct BillingClient {
    inner: Client,
}

impl BillingClient {
    pub fn from_build_env() -> Self {
        let base_url = if env!("AKIRA_BILLING_URL").is_empty() {
            "http://billing.test".to_string()
        } else {
            env!("AKIRA_BILLING_URL").to_string()
        };
        let secret = env!("AKIRA_BILLING_SECRET").to_string();
        Self {
            inner: Client::new(base_url, PRODUCT_SLUG, secret),
        }
    }

    pub fn inner(&self) -> &Client {
        &self.inner
    }

    pub fn inner_mut(&mut self) -> &mut Client {
        &mut self.inner
    }

    #[allow(dead_code)]
    pub fn set_customer_token(&mut self, token: impl Into<String>) {
        self.inner.set_customer_token(token);
    }
}
