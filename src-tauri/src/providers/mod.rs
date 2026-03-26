pub mod dto;
pub mod drivers;
pub mod enums;
pub mod registry;

use std::sync::Arc;

use crate::providers::registry::ProviderFactory;
use crate::app::support::error::AppResult;

pub fn default_registry() -> AppResult<ProviderFactory> {
    let mut registry = ProviderFactory::new();

    registry.register(Arc::new(drivers::github::GitHubFactory::new()));
    registry.register(Arc::new(drivers::gitlab::GitLabFactory::new()));
    registry.register(Arc::new(drivers::bitbucket::BitbucketFactory::new()));
    registry.register(Arc::new(drivers::linear::LinearFactory::new()));

    Ok(registry)
}
