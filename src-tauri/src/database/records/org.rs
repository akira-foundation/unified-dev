use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct OrgSummary {
    pub id: String,
    pub name: String,
    pub provider_id: Option<String>,
    pub external_id: Option<String>,
    pub created_at: String,
    pub selected_repos_count: i64,
    pub last_synced_at: Option<String>,
}
