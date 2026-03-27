use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct PullRequestRecord {
    pub id: String,
    pub external_id: String,
    pub provider: String,
    pub org_id: String,
    pub repo_name: String,
    pub number: i64,
    pub title: String,
    pub body: Option<String>,
    pub state: String,
    pub url: String,
    pub head: String,
    pub base: String,
    pub head_sha: String,
    pub is_draft: bool,
    pub merged_at: Option<String>,
    pub author: Option<String>,
    pub labels: String,
    pub reviewers: String,
    pub ci_status: Option<String>,
    pub created_at: String,
    pub updated_at: String,
    pub synced_at: String,
}
