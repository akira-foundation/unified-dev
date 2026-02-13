use async_trait::async_trait;

use crate::core::provider::traits::VcsProvider;
use crate::core::provider::types::{ProviderAuth, ProviderId, VcsPullRequest, VcsRepository};
use crate::error::{AppError, AppResult};

pub struct BitbucketDriver;

impl BitbucketDriver {
    pub fn new() -> Self {
        Self
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

    async fn list_repositories(&self, _organization: &str, _auth: &ProviderAuth) -> AppResult<Vec<VcsRepository>> {
        Err(AppError::Provider("Bitbucket driver not implemented".to_string()))
    }

    async fn list_pull_requests(
        &self,
        _owner: &str,
        _repository: &str,
        _auth: &ProviderAuth,
    ) -> AppResult<Vec<VcsPullRequest>> {
        Err(AppError::Provider("Bitbucket driver not implemented".to_string()))
    }
}
