use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct AutopilotJobRecord {
    pub id: String,
    pub repo_id: String,
    pub repo_name: String,
    pub config: String,
    pub issues: String,
    pub total: i64,
    pub created: i64,
    pub status: String,
    pub started_at: String,
    pub finished_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct AutopilotThreadRecord {
    pub id: String,
    pub job_id: String,
    pub issue_id: String,
    pub issue_number: i64,
    pub issue_title: String,
    pub thread_id: Option<String>,
    pub status: String,
    pub sort_order: i64,
}

#[allow(dead_code)]
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct AutopilotLogRecord {
    pub id: i64,
    pub job_id: String,
    pub thread_row_id: Option<String>,
    pub event: String,
    pub model_id: Option<String>,
    pub repo_name: String,
    pub issue_id: Option<String>,
    pub issue_number: Option<i64>,
    pub detail: Option<String>,
    pub created_at: String,
}
