use async_trait::async_trait;

use crate::core::provider::traits::{VcsProvider, VcsProviderFactory};
use crate::core::provider::types::{ProviderAuth, ProviderId, ProviderRepo, VcsPullRequest};
use crate::error::{AppError, AppResult};

pub struct BitbucketDriver;

impl BitbucketDriver {
    pub fn new() -> Self {
        Self
    }
}

pub struct BitbucketFactory;

impl BitbucketFactory {
    pub fn new() -> Self {
        Self
    }
}

impl VcsProviderFactory for BitbucketFactory {
    fn id(&self) -> ProviderId {
        ProviderId::Bitbucket
    }

    fn name(&self) -> &str {
        "Bitbucket"
    }

    fn create(&self, _auth: ProviderAuth) -> AppResult<std::sync::Arc<dyn VcsProvider>> {
        Ok(std::sync::Arc::new(BitbucketDriver::new()))
    }
}

#[async_trait]
impl VcsProvider for BitbucketDriver {
    fn id(&self) -> ProviderId {
        ProviderId::Bitbucket
    }

    fn name(&self) -> &str {
        "Bitbucket"
    }

    async fn list_repositories(&self) -> AppResult<Vec<ProviderRepo>> {
        Err(AppError::Provider("Bitbucket driver not implemented".to_string()))
    }

    async fn list_pull_requests(
        &self,
        _owner: &str,
        _repository: &str,
    ) -> AppResult<Vec<VcsPullRequest>> {
        Err(AppError::Provider("Bitbucket driver not implemented".to_string()))
    }
}
