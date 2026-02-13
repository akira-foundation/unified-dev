use async_trait::async_trait;

use crate::core::provider::traits::{VcsProvider, VcsProviderFactory};
use crate::core::provider::types::{ProviderAuth, ProviderId, ProviderRepo, VcsPullRequest};
use crate::error::{AppError, AppResult};

pub struct GitLabDriver;

impl GitLabDriver {
    pub fn new() -> Self {
        Self
    }
}

pub struct GitLabFactory;

impl GitLabFactory {
    pub fn new() -> Self {
        Self
    }
}

impl VcsProviderFactory for GitLabFactory {
    fn id(&self) -> ProviderId {
        ProviderId::GitLab
    }

    fn name(&self) -> &str {
        "GitLab"
    }

    fn create(&self, _auth: ProviderAuth) -> AppResult<std::sync::Arc<dyn VcsProvider>> {
        Ok(std::sync::Arc::new(GitLabDriver::new()))
    }
}

#[async_trait]
impl VcsProvider for GitLabDriver {
    fn id(&self) -> ProviderId {
        ProviderId::GitLab
    }

    fn name(&self) -> &str {
        "GitLab"
    }

    async fn list_repositories(&self) -> AppResult<Vec<ProviderRepo>> {
        Err(AppError::Provider("GitLab driver not implemented".to_string()))
    }

    async fn list_pull_requests(
        &self,
        _owner: &str,
        _repository: &str,
    ) -> AppResult<Vec<VcsPullRequest>> {
        Err(AppError::Provider("GitLab driver not implemented".to_string()))
    }
}
