use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct ProviderRecord {
    pub id: String,
    pub name: String,
    pub kind: String,
    pub auth_type: String,
    pub auth_payload: String,
    pub created_at: String,
    pub account_login: Option<String>,
    pub account_type: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct ProviderSummary {
    pub id: String,
    pub name: String,
    pub kind: String,
    pub auth_type: String,
    pub created_at: String,
    pub account_login: Option<String>,
    pub account_type: Option<String>,
}
