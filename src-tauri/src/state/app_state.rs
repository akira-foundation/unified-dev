use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use akira_billing::gate::Gate;
use sqlx::SqlitePool;
use tokio::sync::RwLock;
use tokio::task::JoinHandle;

use crate::app::billing::BillingClient;
use crate::app::license;
use crate::app::support::error::{AppError, AppResult};
use crate::app::support::security::TokenCipher;
use crate::providers::registry::ProviderFactory;
use crate::tracker::TrackerRegistry;

pub struct AppState {
    pub provider_factory: Arc<ProviderFactory>,
    pub token_cipher: Arc<TokenCipher>,
    db: Arc<RwLock<Option<SqlitePool>>>,
    pub abort_handles: Arc<Mutex<HashMap<String, JoinHandle<()>>>>,
    pub billing: Arc<RwLock<BillingClient>>,
    pub tracker_registry: Arc<TrackerRegistry>,
    pub license_gate: Arc<Gate>,
}

impl AppState {
    pub fn new(provider_factory: Arc<ProviderFactory>, token_cipher: Arc<TokenCipher>) -> Self {
        let db: Arc<RwLock<Option<SqlitePool>>> = Arc::new(RwLock::new(None));
        let license_gate = license::gate::build(db.clone());
        Self {
            provider_factory,
            token_cipher,
            db,
            abort_handles: Arc::new(Mutex::new(HashMap::new())),
            billing: Arc::new(RwLock::new(BillingClient::from_build_env())),
            tracker_registry: Arc::new(TrackerRegistry::new()),
            license_gate,
        }
    }

    pub async fn pool(&self) -> AppResult<SqlitePool> {
        self.db
            .read()
            .await
            .clone()
            .ok_or(AppError::Unauthenticated)
    }

    pub async fn set_pool(&self, pool: SqlitePool) {
        *self.db.write().await = Some(pool);
    }

    pub async fn clear_pool(&self) {
        *self.db.write().await = None;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::app::support::security::TokenCipher;
    use crate::providers::registry::ProviderFactory;
    use crate::test_utils::setup_test_db;

    fn build_state() -> AppState {
        AppState::new(
            Arc::new(ProviderFactory::new()),
            Arc::new(TokenCipher::new([0u8; 32])),
        )
    }

    #[tokio::test]
    async fn pool_is_unauthenticated_until_set() {
        let state = build_state();

        assert!(matches!(
            state.pool().await,
            Err(AppError::Unauthenticated)
        ));

        state.set_pool(setup_test_db().await).await;
        assert!(state.pool().await.is_ok());
    }

    #[tokio::test]
    async fn clear_pool_reverts_to_unauthenticated() {
        let state = build_state();
        state.set_pool(setup_test_db().await).await;
        assert!(state.pool().await.is_ok());

        state.clear_pool().await;

        assert!(matches!(
            state.pool().await,
            Err(AppError::Unauthenticated)
        ));
    }
}
