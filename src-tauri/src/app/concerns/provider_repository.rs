use async_trait::async_trait;

use crate::database::records::{ProviderRecord, ProviderSummary};
use crate::app::support::error::AppResult;

#[async_trait]
pub trait ProviderRepository: Send + Sync {
    async fn create(&self, provider: &ProviderRecord) -> AppResult<ProviderSummary>;
    async fn delete(&self, provider_id: &str) -> AppResult<()>;
    async fn list(&self) -> AppResult<Vec<ProviderSummary>>;
    async fn find_by_id(&self, provider_id: &str) -> AppResult<ProviderRecord>;
    async fn update_auth(&self, provider_id: &str, auth_type: &str, auth_payload: &str) -> AppResult<()>;
}
