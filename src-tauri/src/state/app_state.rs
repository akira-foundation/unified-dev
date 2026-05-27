use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use tokio::sync::RwLock;
use tokio::task::JoinHandle;

use crate::app::billing::BillingClient;
use crate::app::support::security::TokenCipher;
use crate::providers::registry::ProviderFactory;
use crate::tracker::TrackerRegistry;

pub struct AppState {
    pub provider_factory: Arc<ProviderFactory>,
    pub token_cipher: Arc<TokenCipher>,
    pub db_pool: sqlx::SqlitePool,
    pub abort_handles: Arc<Mutex<HashMap<String, JoinHandle<()>>>>,
    pub billing: Arc<RwLock<BillingClient>>,
    pub tracker_registry: Arc<TrackerRegistry>,
}

impl AppState {
    pub fn new(
        provider_factory: Arc<ProviderFactory>,
        token_cipher: Arc<TokenCipher>,
        db_pool: sqlx::SqlitePool,
    ) -> Self {
        Self {
            provider_factory,
            token_cipher,
            db_pool,
            abort_handles: Arc::new(Mutex::new(HashMap::new())),
            billing: Arc::new(RwLock::new(BillingClient::from_build_env())),
            tracker_registry: Arc::new(TrackerRegistry::new()),
        }
    }
}
