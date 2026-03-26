pub mod bitbucket;
pub mod github;
pub mod gitlab;
pub mod linear;
pub mod registry;
pub mod traits;
pub mod types;

use std::sync::Arc;

use crate::providers::registry::ProviderFactory;
use crate::support::error::AppResult;

pub fn default_registry() -> AppResult<ProviderFactory> {
    let mut registry = ProviderFactory::new();

    registry.register(Arc::new(github::GitHubFactory::new()));
    registry.register(Arc::new(gitlab::GitLabFactory::new()));
    registry.register(Arc::new(bitbucket::BitbucketFactory::new()));
    registry.register(Arc::new(linear::LinearFactory::new()));

    Ok(registry)
}
