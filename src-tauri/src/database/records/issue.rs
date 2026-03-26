use serde::{Deserialize, Serialize};

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
    pub sync_with_provider: bool,
}
