use serde::{Deserialize, Serialize};

use crate::core::provider::types::ProviderAuth;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppConfig {
    pub organizations: Vec<OrganizationConfig>,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct OrganizationConfig {
    pub id: String,
    pub name: String,
    pub provider_id: String,
    pub auth_json: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct OrganizationSummary {
    pub id: String,
    pub name: String,
    pub provider_id: String,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct OrganizationRepoSummary {
    pub id: i64,
    pub organization_id: String,
    pub owner: String,
    pub repo_name: String,
    pub auto_sync: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateOrganizationInput {
    pub name: String,
    pub provider_id: String,
    pub auth: ProviderAuth,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AttachRepoInput {
    pub organization_id: String,
    pub owner: String,
    pub repo_name: String,
    pub auto_sync: Option<bool>,
}
