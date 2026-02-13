use async_trait::async_trait;

use crate::core::provider::traits::VcsProvider;
use crate::core::provider::types::{ProviderAuth, ProviderId, VcsPullRequest, VcsRepository};
use crate::error::{AppError, AppResult};

pub struct GitLabDriver;

impl GitLabDriver {
    pub fn new() -> Self {
        Self
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

    async fn list_repositories(&self, _organization: &str, _auth: &ProviderAuth) -> AppResult<Vec<VcsRepository>> {
        Err(AppError::Provider("GitLab driver not implemented".to_string()))
    }

    async fn list_pull_requests(
        &self,
        _owner: &str,
        _repository: &str,
        _auth: &ProviderAuth,
    ) -> AppResult<Vec<VcsPullRequest>> {
        Err(AppError::Provider("GitLab driver not implemented".to_string()))
    }
}
