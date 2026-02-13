pub mod bitbucket;
pub mod github;
pub mod gitlab;

use std::sync::Arc;

use crate::core::provider::registry::ProviderRegistry;
use crate::error::AppResult;

pub fn default_registry() -> AppResult<ProviderRegistry> {
    let mut registry = ProviderRegistry::new();

    registry.register(Arc::new(github::GitHubDriver::new()?));
    registry.register(Arc::new(gitlab::GitLabDriver::new()));
    registry.register(Arc::new(bitbucket::BitbucketDriver::new()));

    Ok(registry)
}
