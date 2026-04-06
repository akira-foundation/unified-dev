#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct ProviderRepo {
    pub id: String,
    pub owner: String,
    pub name: String,
    pub visibility: String,
    pub is_private: bool,
    pub default_branch: String,
    pub is_fork: bool,
    pub fork_owner: Option<String>,
    pub fork_repo: Option<String>,
}
