use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VcsRepoLabel {
    pub name: String,
    pub color: String,
    pub description: Option<String>,
}
