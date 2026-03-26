use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize)]
pub struct LocalRepository {
    pub id: String,
    pub name: String,
    pub default_branch: String,
    pub source_path: String,
    pub workspace_root: String,
    pub created_at: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct AddLocalRepositoryResponse {
    pub repository: LocalRepository,
    pub thread: crate::app::threads::ThreadConfig,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct FileChange {
    pub filename: String,
    pub status: String,
    pub diff: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct PrInfo {
    pub url: String,
    pub is_draft: bool,
}
