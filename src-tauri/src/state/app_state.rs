use std::sync::Arc;

use crate::app::concerns::OrganizationRepoRepository;
use crate::app::concerns::ProviderRepository;
use crate::providers::registry::ProviderFactory;
use crate::app::support::security::TokenCipher;

pub struct AppState {
    pub provider_repo: Arc<dyn ProviderRepository>,
    pub organization_repos: Arc<dyn OrganizationRepoRepository>,
    pub provider_factory: Arc<ProviderFactory>,
    pub token_cipher: Arc<TokenCipher>,
    pub db_pool: sqlx::SqlitePool,
}

impl AppState {
    pub fn new(
        provider_repo: Arc<dyn ProviderRepository>,
        organization_repos: Arc<dyn OrganizationRepoRepository>,
        provider_factory: Arc<ProviderFactory>,
        token_cipher: Arc<TokenCipher>,
        db_pool: sqlx::SqlitePool,
    ) -> Self {
        Self {
            provider_repo,
            organization_repos,
            provider_factory,
            token_cipher,
            db_pool,
        }
    }
}
