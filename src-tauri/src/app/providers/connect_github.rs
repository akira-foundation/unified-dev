use tauri::State;

use crate::database::records::ProviderSummary;
use crate::providers::drivers::github::oauth;
use crate::providers::enums::ProviderAuth;
use crate::state::AppState;

pub async fn connect_github(state: State<'_, AppState>, app: tauri::AppHandle) -> Result<ProviderSummary, String> {
    use tauri_plugin_opener::OpenerExt;
    use tokio::net::TcpListener;

    let client_id = env!("GITHUB_CLIENT_ID");
    let api_url = env!("AKIRA_API_URL");

    let listener = TcpListener::bind("127.0.0.1:4567")
        .await
        .map_err(|e| format!("Failed to bind callback listener: {e}"))?;

    let oauth_url = format!(
        "https://github.com/login/oauth/authorize?client_id={client_id}&redirect_uri=http%3A%2F%2Flocalhost%3A4567&scope=repo%2Cread%3Aorg"
    );
    app.opener()
        .open_url(&oauth_url, None::<&str>)
        .map_err(|e| format!("Failed to open browser: {e}"))?;

    let code = oauth::await_callback(listener)
        .await
        .map_err(|e| e.to_string())?;

    let result = oauth::exchange_code(api_url, &code)
        .await
        .map_err(|e| e.to_string())?;

    let auth = ProviderAuth::GitHubOAuth {
        access_token: result.access_token,
        refresh_token: result.refresh_token,
        expires_at: result.expires_at,
    };

    let (auth_type, auth_payload) = crate::app::providers::credentials::serialize_auth(&state, &auth)
        .map_err(|e| e.to_string())?;

    state
        .provider_repo
        .create(&crate::database::records::ProviderRecord {
            id: uuid::Uuid::new_v4().to_string(),
            name: result.account_login.clone(),
            kind: "github".to_string(),
            auth_type,
            auth_payload,
            created_at: time::OffsetDateTime::now_utc().format(&time::format_description::well_known::Rfc3339).unwrap_or_default(),
            account_login: Some(result.account_login),
            account_type: Some(result.account_type),
        })
        .await
        .map_err(|e| e.to_string())
}
