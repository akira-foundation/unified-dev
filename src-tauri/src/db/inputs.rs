use serde::{Deserialize, Serialize};

use crate::providers::types::ProviderAuth;

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
    pub default_branch: Option<String>,
    pub open_prs_count: Option<i64>,
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

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateIssueInput {
    pub org_id: String,
    pub repo_name: String,
    pub title: String,
    pub body: Option<String>,
    pub labels: Vec<String>,
    pub assignees: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UpdateIssueInput {
    pub title: Option<String>,
    pub body: Option<String>,
    pub status: Option<String>,
    pub labels: Option<Vec<String>>,
    pub assignees: Option<Vec<String>>,
}
