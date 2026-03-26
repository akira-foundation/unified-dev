use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateIssueRequest {
    pub org_id: String,
    pub repo_name: String,
    pub title: String,
    pub body: Option<String>,
    pub labels: Vec<String>,
    pub assignees: Vec<String>,
    #[serde(default = "default_sync_with_provider")]
    pub sync_with_provider: bool,
}

fn default_sync_with_provider() -> bool {
    true
}
