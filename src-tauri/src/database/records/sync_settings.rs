use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct SyncSettingsRecord {
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
    pub created_at: String,
    pub updated_at: String,
}
