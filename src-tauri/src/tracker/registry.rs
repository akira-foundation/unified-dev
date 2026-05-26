use std::sync::Arc;

use crate::app::support::error::{AppError, AppResult};

use super::drivers::jira::JiraTracker;
use super::drivers::linear::LinearTracker;
use super::tracker::Tracker;

const PROVIDERS: &[&str] = &["linear", "jira"];

pub struct TrackerRegistry;

impl TrackerRegistry {
    pub fn new() -> Self {
        Self
    }

    pub fn build(&self, kind: &str, token: impl Into<String>) -> AppResult<Arc<dyn Tracker>> {
        match kind {
            "linear" => Ok(Arc::new(LinearTracker::new(token))),
            "jira" => Ok(Arc::new(JiraTracker::new(token)?)),
            other => Err(AppError::Provider(format!("unknown tracker kind: {other}"))),
        }
    }

    pub fn supports(&self, kind: &str) -> bool {
        PROVIDERS.contains(&kind)
    }

    pub fn providers(&self) -> Vec<String> {
        PROVIDERS.iter().map(|kind| kind.to_string()).collect()
    }
}

impl Default for TrackerRegistry {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn builds_linear_and_rejects_unknown() {
        let registry = TrackerRegistry::new();
        assert!(registry.supports("linear"));
        assert!(registry.build("linear", "tok").is_ok());
        assert!(registry.build("mystery", "tok").is_err());
    }

    #[test]
    fn builds_jira_with_credentials() {
        let registry = TrackerRegistry::new();
        assert!(registry.supports("jira"));
        assert!(registry
            .build("jira", "https://site.atlassian.net|me@example.com|token")
            .is_ok());
        assert!(registry.build("jira", "missing-parts").is_err());
    }
}
