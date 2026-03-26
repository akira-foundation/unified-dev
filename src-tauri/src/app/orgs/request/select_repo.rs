use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SelectRepoRequest {
    pub owner: String,
    pub repo_name: String,
    pub visibility: String,
    pub is_selected: bool,
    pub auto_sync: Option<bool>,
    pub default_branch: Option<String>,
    pub open_prs_count: Option<i64>,
}
