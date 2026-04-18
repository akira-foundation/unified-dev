use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize)]
pub struct SaveJobRequest {
    pub id: String,
    pub repo_id: String,
    pub repo_name: String,
    pub config: String,
    pub issues: String,
    pub total: i64,
    pub started_at: String,
}

#[derive(Debug, Deserialize)]
pub struct UpdateJobRequest {
    pub id: String,
    pub created: i64,
    pub status: String,
    pub finished_at: Option<String>,
    pub issues: Option<String>,
    pub total: Option<i64>,
}

#[derive(Debug, Deserialize)]
pub struct SaveThreadRequest {
    pub id: String,
    pub job_id: String,
    pub issue_id: String,
    pub issue_number: i64,
    pub issue_title: String,
    pub sort_order: i64,
}

#[derive(Debug, Deserialize)]
pub struct UpdateThreadRequest {
    pub id: String,
    pub thread_id: Option<String>,
    pub status: String,
}

#[derive(Debug, Deserialize)]
pub struct DeleteThreadRequest {
    pub thread_row_id: String,
}

#[derive(Debug, Deserialize)]
pub struct WriteLogRequest {
    pub job_id: String,
    pub thread_row_id: Option<String>,
    pub event: String,
    pub model_id: Option<String>,
    pub repo_name: String,
    pub issue_id: Option<String>,
    pub issue_number: Option<i64>,
    pub detail: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AutopilotJobDto {
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
    pub threads: Vec<AutopilotThreadDto>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AutopilotThreadDto {
    pub id: String,
    pub job_id: String,
    pub issue_id: String,
    pub issue_number: i64,
    pub issue_title: String,
    pub thread_id: Option<String>,
    pub status: String,
    pub sort_order: i64,
}
