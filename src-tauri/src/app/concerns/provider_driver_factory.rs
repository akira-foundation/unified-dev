use std::sync::Arc;

use async_trait::async_trait;

use crate::providers::enums::{ProviderAuth, ProviderKind};
use crate::app::support::error::AppResult;

use super::vcs_provider::VcsProvider;

#[async_trait]
pub trait ProviderDriverFactory: Send + Sync {
    fn kind(&self) -> ProviderKind;
    async fn create(&self, auth: ProviderAuth) -> AppResult<Arc<dyn VcsProvider>>;
}
