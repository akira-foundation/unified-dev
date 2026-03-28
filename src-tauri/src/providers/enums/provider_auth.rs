#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(tag = "auth_type", content = "auth_payload")]
pub enum ProviderAuth {
    #[serde(rename = "pat")]
    PersonalAccessToken { token: String },

    #[serde(rename = "github_oauth")]
    GitHubOAuth {
        access_token: String,
        refresh_token: Option<String>,
        expires_at: Option<i64>,
    },

    #[serde(rename = "github_app")]
    GitHubApp {
        oauth_access_token: String,
        installation_token: String,
        installation_id: i64,
        expires_at: i64,
    },

    #[serde(rename = "app_password")]
    AppPassword { username: String, password: String },
}
