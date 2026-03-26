use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct OrgRecord {
    pub id: String,
    pub name: String,
    pub provider_id: Option<String>,
    pub external_id: Option<String>,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct OrgSummary {
    pub id: String,
    pub name: String,
    pub provider_id: Option<String>,
    pub external_id: Option<String>,
    pub created_at: String,
}
