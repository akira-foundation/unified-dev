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
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct ProviderSummary {
    pub id: String,
    pub name: String,
    pub kind: String,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateProviderInput {
    pub name: String,
    pub kind: String,
    pub auth: ProviderAuth,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct OrganizationRecord {
    pub id: String,
    pub name: String,
    pub provider_id: String,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct OrganizationSummary {
    pub id: String,
    pub name: String,
    pub provider_id: String,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateOrganizationInput {
    pub name: String,
    pub provider_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProviderAuthPayload {
    pub token: String,
}
