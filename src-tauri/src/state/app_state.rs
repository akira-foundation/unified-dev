use std::sync::Arc;

use crate::app::support::security::TokenCipher;
use crate::providers::registry::ProviderFactory;

pub struct AppState {
    pub provider_factory: Arc<ProviderFactory>,
    pub token_cipher: Arc<TokenCipher>,
    pub db_pool: sqlx::SqlitePool,
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
        }
    }
}
