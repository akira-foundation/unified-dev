use serde::{Deserialize, Serialize};

use crate::core::provider::types::ProviderAuth;

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
    pub created_at: String,
    pub account_login: Option<String>,
    pub account_type: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateProviderInput {
    pub name: String,
    pub kind: String,
    pub auth: ProviderAuth,
    #[serde(default)]
    pub account_login: Option<String>,
    #[serde(default)]
    pub account_type: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UpdateProviderAuthInput {
    pub provider_id: String,
    pub auth: ProviderAuth,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TestProviderInput {
    pub kind: String,
    pub auth: ProviderAuth,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct OrganizationRecord {
    pub id: String,
    pub name: String,
    pub provider_id: Option<String>,
    pub external_id: Option<String>,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct OrganizationSummary {
    pub id: String,
    pub name: String,
    pub provider_id: Option<String>,
    pub external_id: Option<String>,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct OrganizationRepoSummary {
    pub id: i64,
    pub organization_id: String,
    pub owner: String,
    pub repo_name: String,
    pub visibility: String,
    pub is_selected: bool,
    pub auto_sync: bool,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct OrganizationRepoWithOrg {
    pub id: i64,
    pub organization_id: String,
    pub organization_name: String,
    pub owner: String,
    pub repo_name: String,
    pub visibility: String,
    pub is_selected: bool,
    pub auto_sync: bool,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateOrganizationInput {
    pub name: String,
    pub provider_id: String,
    pub external_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UpdateOrganizationInput {
    pub id: String,
    pub name: String,
    pub provider_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SelectedRepositoryInput {
    pub owner: String,
    pub repo_name: String,
    pub visibility: String,
    pub is_selected: bool,
    pub auto_sync: Option<bool>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProviderAuthPayload {
    pub token: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitHubOAuthPayload {
    pub access_token_enc: String,
    pub refresh_token_enc: Option<String>,
    pub expires_at: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppPasswordAuthPayload {
    pub username: String,
    pub password_enc: String,
}
