use tauri::State;

use serde::Deserialize;

use crate::core::provider::types::{ProviderAuth, ProviderKind, ProviderOrg, ProviderRepo};
use crate::db::models::{CreateProviderInput, ProviderSummary, TestProviderInput, UpdateProviderAuthInput};
use crate::state::AppState;

#[derive(Debug, Deserialize)]
pub struct ProviderReposInput {
    pub provider_id: String,
    pub scope: String,
    pub organization_login: Option<String>,
}

#[tauri::command]
pub async fn create_provider(
    state: State<'_, AppState>,
    input: CreateProviderInput,
) -> Result<ProviderSummary, String> {
    state
        .provider_service
        .create_provider(input)
        .await
        .map_err(|error| error.to_string())
}

#[tauri::command]
pub async fn list_providers(state: State<'_, AppState>) -> Result<Vec<ProviderSummary>, String> {
    state
        .provider_service
        .list_providers()
        .await
        .map_err(|error| error.to_string())
}

#[tauri::command]
pub async fn update_provider_auth(
    state: State<'_, AppState>,
    input: UpdateProviderAuthInput,
) -> Result<(), String> {
    state
        .provider_service
        .update_provider_auth(input)
        .await
        .map_err(|error| error.to_string())
}

#[tauri::command]
pub async fn delete_provider(
    state: State<'_, AppState>,
    provider_id: String,
    keep_organizations: bool,
) -> Result<(), String> {
    state
        .provider_service
        .delete_provider(&provider_id, keep_organizations)
        .await
        .map_err(|error| error.to_string())
}

#[tauri::command]
pub async fn test_provider_connection(
    state: State<'_, AppState>,
    input: TestProviderInput,
) -> Result<(), String> {
    let kind = ProviderKind::from_str(&input.kind);
    let provider = state
        .provider_factory
        .create(&kind, input.auth)
        .await
        .map_err(|error| error.to_string())?;

    provider
        .validate_auth()
        .await
        .map_err(|error| error.to_string())
}

#[tauri::command]
pub async fn connect_github(
    state: State<'_, AppState>,
    app: tauri::AppHandle,
) -> Result<ProviderSummary, String> {
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

    let code = await_github_callback(listener)
        .await
        .map_err(|e| e.to_string())?;

    let result = exchange_github_code(api_url, &code)
        .await
        .map_err(|e| e.to_string())?;

    state
        .provider_service
        .create_provider(CreateProviderInput {
            name: result.account_login.clone(),
            kind: "github".to_string(),
            auth: ProviderAuth::GitHubOAuth {
                access_token: result.access_token,
                refresh_token: result.refresh_token,
                expires_at: result.expires_at,
            },
            account_login: Some(result.account_login),
            account_type: Some(result.account_type),
        })
        .await
        .map_err(|e| e.to_string())
}

struct ConnectResult {
    access_token: String,
    refresh_token: Option<String>,
    expires_at: Option<i64>,
    account_login: String,
    account_type: String,
}

async fn exchange_github_code(
    api_url: &str,
    code: &str,
) -> crate::error::AppResult<ConnectResult> {
    use crate::error::AppError;

    #[derive(serde::Deserialize)]
    struct ConnectResponse {
        access_token: String,
        refresh_token: Option<String>,
        expires_at: Option<i64>,
        account_login: String,
        account_type: String,
    }

    let client = reqwest::Client::builder()
        .user_agent("UnifiedDev/1.0")
        .build()?;

    let url = format!("{api_url}/github/connect");
    let response = client
        .post(&url)
        .header("Content-Type", "application/json")
        .json(&serde_json::json!({ "code": code }))
        .send()
        .await?;

    if !response.status().is_success() {
        let status = response.status();
        return Err(AppError::Provider(format!(
            "GitHub OAuth proxy failed: {status}"
        )));
    }

    let result: ConnectResponse = response.json().await?;

    Ok(ConnectResult {
        access_token: result.access_token,
        refresh_token: result.refresh_token,
        expires_at: result.expires_at,
        account_login: result.account_login,
        account_type: result.account_type,
    })
}

async fn await_github_callback(listener: tokio::net::TcpListener) -> crate::error::AppResult<String> {
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    use crate::error::AppError;

    let (mut stream, _) = listener.accept().await?;

    let mut buf = vec![0u8; 4096];
    let n = stream.read(&mut buf).await?;
    let request = String::from_utf8_lossy(&buf[..n]);

    let code = request
        .lines()
        .next()
        .and_then(|line| line.split_whitespace().nth(1))
        .and_then(|path| path.split('?').nth(1))
        .and_then(|query| {
            query.split('&').find_map(|pair| {
                let mut parts = pair.splitn(2, '=');
                let key = parts.next()?;
                let value = parts.next()?;
                if key == "code" { Some(value.to_string()) } else { None }
            })
        })
        .ok_or_else(|| AppError::Provider("code not found in GitHub callback".to_string()))?;

    let body = "<html><body><h2>Connected! You can close this tab.</h2></body></html>";
    let response = format!(
        "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
        body.len(),
        body
    );
    stream.write_all(response.as_bytes()).await?;

    Ok(code)
}

#[tauri::command]
pub async fn list_provider_organizations(
    state: State<'_, AppState>,
    provider_id: String,
) -> Result<Vec<ProviderOrg>, String> {
    let credentials = state
        .provider_service
        .credentials(&provider_id)
        .await
        .map_err(|error| error.to_string())?;

    let provider = state
        .provider_factory
        .create(&credentials.kind, credentials.auth)
        .await
        .map_err(|error| error.to_string())?;

    provider
        .list_organizations()
        .await
        .map_err(|error| error.to_string())
}

#[tauri::command]
pub async fn list_provider_repositories(
    state: State<'_, AppState>,
    input: ProviderReposInput,
) -> Result<Vec<ProviderRepo>, String> {
    let credentials = state
        .provider_service
        .credentials(&input.provider_id)
        .await
        .map_err(|error| error.to_string())?;

    let provider = state
        .provider_factory
        .create(&credentials.kind, credentials.auth)
        .await
        .map_err(|error| error.to_string())?;

    match input.scope.as_str() {
        "personal" => provider
            .list_repositories()
            .await
            .map_err(|error| error.to_string()),
        "organization" => {
            let login = input
                .organization_login
                .ok_or_else(|| "organization_login is required".to_string())?;
            provider
                .list_organization_repositories(&login)
                .await
                .map_err(|error| error.to_string())
        }
        _ => Err("invalid scope".to_string()),
    }
}
