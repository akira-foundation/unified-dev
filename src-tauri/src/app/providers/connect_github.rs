use tauri::State;

use crate::database::records::ProviderSummary;
use crate::providers::drivers::github::oauth;
use crate::providers::enums::ProviderAuth;
use crate::state::AppState;

pub async fn connect_github(state: State<'_, AppState>, app: tauri::AppHandle) -> Result<ProviderSummary, String> {
    use tauri_plugin_opener::OpenerExt;

    let app_slug = option_env!("GITHUB_APP_SLUG").unwrap_or("akira-apps-unified-dev");
    let api_url = env!("AKIRA_API_URL");
    let oauth_state = uuid::Uuid::new_v4().to_string();

    let listener = oauth::bind_callback_listener()
        .await
        .map_err(|e| e.to_string())?;

    let client_id = option_env!("GITHUB_OAUTH_CLIENT_ID").unwrap_or(env!("GITHUB_CLIENT_ID"));
    let oauth_url = format!(
        "https://github.com/login/oauth/authorize?client_id={client_id}&redirect_uri=http%3A%2F%2Flocalhost%3A4567&scope=repo%2Cread%3Aorg%2Cread%3Auser&state={oauth_state}"
    );
    app.opener()
        .open_url(&oauth_url, None::<&str>)
        .map_err(|e| format!("Failed to open browser: {e}"))?;

    let code = oauth::await_callback(listener, &oauth_state)
        .await
        .map_err(|e| e.to_string())?;

    let result = oauth::exchange_code(api_url, &code)
        .await
        .map_err(|e| e.to_string())?;

    let auth = fetch_installation_token(api_url, &result.access_token, result.refresh_token.clone(), result.expires_at).await.map_err(|error| {
        if error.contains("app not installed for this user") {
            let install_url = format!("https://github.com/apps/{app_slug}/installations/select_target");
            let _ = app.opener().open_url(&install_url, None::<&str>);
            return "GitHub App installation required. Complete the installation in the browser, then click Connect again.".to_string();
        }

        error
    })?;

    let api_token = result.access_token.clone();

    let (account_login, account_type) = oauth::fetch_viewer(&api_token)
        .await
        .map_err(|e| e.to_string())?;

    let (auth_type, auth_payload) = crate::app::providers::credentials::serialize_auth(&state, &auth)
        .map_err(|e| e.to_string())?;

    let id = uuid::Uuid::new_v4().to_string();
    let created_at = time::OffsetDateTime::now_utc()
        .format(&time::format_description::well_known::Rfc3339)
        .unwrap_or_default();

    sqlx::query(
        "INSERT INTO providers (id, name, kind, auth_type, auth_payload, created_at, account_login, account_type) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
    )
    .bind(&id)
    .bind(&account_login)
    .bind("github")
    .bind(&auth_type)
    .bind(&auth_payload)
    .bind(&created_at)
    .bind(&account_login)
    .bind(&account_type)
    .execute(&state.db_pool)
    .await
    .map_err(|e| format!("DB insert failed: {e}"))?;

    Ok(crate::database::records::ProviderSummary {
        id,
        name: account_login.clone(),
        kind: "github".to_string(),
        created_at,
        account_login: Some(account_login),
        account_type: Some(account_type),
    })
}

async fn fetch_installation_token(
    api_url: &str,
    oauth_access_token: &str,
    oauth_refresh_token: Option<String>,
    oauth_expires_at: Option<i64>,
) -> Result<ProviderAuth, String> {
    #[derive(serde::Deserialize)]
    struct InstallationTokenResponse {
        token: String,
        expires_at: i64,
        installation_id: i64,
    }

    let client = reqwest::Client::builder()
        .user_agent("UnifiedDev/1.0")
        .build()
        .map_err(|e| e.to_string())?;

    let response = client
        .post(format!("{api_url}/github/installation-token"))
        .header("Content-Type", "application/json")
        .json(&serde_json::json!({ "access_token": oauth_access_token }))
        .send()
        .await
        .map_err(|e| e.to_string())?;

    if !response.status().is_success() {
        let status = response.status();
        let body = response.text().await.map_err(|e| e.to_string())?;
        return Err(format!("installation token request failed: {status} — {body}"));
    }

    let data: InstallationTokenResponse = response.json().await.map_err(|e| e.to_string())?;

    Ok(ProviderAuth::GitHubApp {
        oauth_access_token: oauth_access_token.to_string(),
        oauth_refresh_token,
        oauth_expires_at,
        installation_token: data.token,
        installation_id: data.installation_id,
        expires_at: data.expires_at,
    })
}
