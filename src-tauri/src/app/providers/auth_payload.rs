use serde::{Deserialize, Serialize};

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
