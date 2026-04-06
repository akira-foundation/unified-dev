use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct OrgRepoSummary {
    pub id: i64,
    pub organization_id: String,
    pub owner: String,
    pub repo_name: String,
    pub visibility: String,
    pub is_selected: bool,
    pub auto_sync: bool,
    pub default_branch: String,
    pub open_prs_count: i64,
    pub is_fork: bool,
    pub fork_owner: Option<String>,
    pub fork_repo: Option<String>,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct OrgRepoWithOrg {
    pub id: i64,
    pub organization_id: String,
    pub organization_name: String,
    pub owner: String,
    pub repo_name: String,
    pub visibility: String,
    pub is_selected: bool,
    pub auto_sync: bool,
    pub default_branch: String,
    pub open_prs_count: i64,
    pub is_fork: bool,
    pub fork_owner: Option<String>,
    pub fork_repo: Option<String>,
    pub created_at: String,
}
