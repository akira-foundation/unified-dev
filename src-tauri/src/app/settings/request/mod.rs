use serde::{Deserialize, Serialize};

pub const GLOBAL_ID: &str = "global";

pub const DEFAULT_ISSUES_INTERVAL_SECS: i64 = 900;
pub const DEFAULT_PRS_INTERVAL_SECS: i64 = 300;
pub const DEFAULT_REPOS_INTERVAL_SECS: i64 = 1800;
pub const DEFAULT_ORGS_INTERVAL_SECS: i64 = 7200;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncSettingsDto {
    pub id: String,
    pub scope: String,
    pub sync_issues_enabled: bool,
    pub sync_issues_interval_secs: i64,
    pub sync_prs_enabled: bool,
    pub sync_prs_interval_secs: i64,
    pub sync_repos_enabled: bool,
    pub sync_repos_interval_secs: i64,
    pub sync_orgs_enabled: bool,
    pub sync_orgs_interval_secs: i64,
}

impl SyncSettingsDto {
    pub fn defaults_for(id: &str) -> Self {
        let scope = scope_for_id(id);
        let enabled = !cfg!(debug_assertions);
        Self {
            id: id.to_string(),
            scope: scope.to_string(),
            sync_issues_enabled: enabled,
            sync_issues_interval_secs: DEFAULT_ISSUES_INTERVAL_SECS,
            sync_prs_enabled: enabled,
            sync_prs_interval_secs: DEFAULT_PRS_INTERVAL_SECS,
            sync_repos_enabled: enabled,
            sync_repos_interval_secs: DEFAULT_REPOS_INTERVAL_SECS,
            sync_orgs_enabled: enabled,
            sync_orgs_interval_secs: DEFAULT_ORGS_INTERVAL_SECS,
        }
    }
}

pub fn scope_for_id(id: &str) -> &'static str {
    if id == GLOBAL_ID {
        "global"
    } else if id.contains(':') {
        "repository"
    } else {
        "organization"
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpsertSyncSettingsRequest {
    pub id: String,
    pub sync_issues_enabled: bool,
    pub sync_issues_interval_secs: i64,
    pub sync_prs_enabled: bool,
    pub sync_prs_interval_secs: i64,
    pub sync_repos_enabled: bool,
    pub sync_repos_interval_secs: i64,
    pub sync_orgs_enabled: bool,
    pub sync_orgs_interval_secs: i64,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn defaults_mirror_debug_flag() {
        let d = SyncSettingsDto::defaults_for(GLOBAL_ID);
        let expected = !cfg!(debug_assertions);
        assert_eq!(d.sync_issues_enabled, expected);
        assert_eq!(d.sync_prs_enabled, expected);
        assert_eq!(d.sync_repos_enabled, expected);
        assert_eq!(d.sync_orgs_enabled, expected);
    }
}
