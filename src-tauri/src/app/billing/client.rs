use akira_billing::Client;

/// Product slug shipped to the Akira Billing API. Hard-coded by design — the
/// app is single-product and the slug is part of every request signature.
pub const PRODUCT_SLUG: &str = "unified-dev";

/// Wrapper around `akira_billing::Client` that carries our build-time
/// configuration. `customer_token` is mutated as soon as OTP verification
/// returns a Sanctum bearer.
#[derive(Debug, Clone)]
pub struct BillingClient {
    inner: Client,
}

impl BillingClient {
    /// Build a client from the build-time envs. Empty `secret`/`url` are
    /// accepted in debug builds so contributors without secrets can still
    /// compile the app; release builds reject empty envs in `build.rs`.
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

    /// Borrow the underlying SDK client. Read-only operations can hit this
    /// directly.
    pub fn inner(&self) -> &Client {
        &self.inner
    }

    /// Mutable access used by OTP verification and any other flow that needs
    /// to install a Sanctum bearer on the client.
    pub fn inner_mut(&mut self) -> &mut Client {
        &mut self.inner
    }

    /// Replace the inner client with one carrying the given bearer. Useful
    /// after restoring a persisted token at startup.
    pub fn set_customer_token(&mut self, token: impl Into<String>) {
        self.inner.set_customer_token(token);
    }
}
