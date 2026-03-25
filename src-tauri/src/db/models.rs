use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct ProviderRecord {
    pub id: String,
    pub name: String,
    pub kind: String,
    pub auth_type: String,
    pub auth_payload: String,
    pub created_at: String,
    pub account_login: Option<String>,
    pub account_type: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct ProviderSummary {
    pub id: String,
    pub name: String,
    pub kind: String,
    pub created_at: String,
    pub account_login: Option<String>,
    pub account_type: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct OrganizationRecord {
    pub id: String,
    pub name: String,
    pub provider_id: Option<String>,
    pub external_id: Option<String>,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct OrganizationSummary {
    pub id: String,
    pub name: String,
    pub provider_id: Option<String>,
    pub external_id: Option<String>,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct OrganizationRepoSummary {
    pub id: i64,
    pub organization_id: String,
    pub owner: String,
    pub repo_name: String,
    pub visibility: String,
    pub is_selected: bool,
    pub auto_sync: bool,
    pub default_branch: String,
    pub open_prs_count: i64,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct OrganizationRepoWithOrg {
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
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct IssueRecord {
    pub id: String,
    pub external_id: String,
    pub provider: String,
    pub org_id: String,
    pub repo_name: String,
    pub number: i64,
    pub title: String,
    pub body: Option<String>,
    pub status: String,
    pub state_reason: Option<String>,
    pub labels: String,
    pub label_colors: String,
    pub assignees: String,
    pub author: Option<String>,
    pub url: String,
    pub linked_pr_numbers: String,
    pub created_at: String,
    pub updated_at: String,
    pub synced_at: String,
}
