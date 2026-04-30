use base64::Engine;
use rand::RngCore;
use sha2::{Digest, Sha256};
use tauri::AppHandle;
use tauri_plugin_opener::OpenerExt;

use crate::app::support::error::{AppError, AppResult};

fn generate_pkce() -> (String, String) {
    let mut bytes = [0u8; 32];
    rand::rng().fill_bytes(&mut bytes);
    let verifier = base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(bytes);
    let digest = Sha256::digest(verifier.as_bytes());
    let challenge = base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(digest);
    (verifier, challenge)
}

static CALLBACK_ABORT: std::sync::OnceLock<tokio::sync::Mutex<Option<tokio::sync::oneshot::Sender<()>>>> =
    std::sync::OnceLock::new();

fn callback_abort() -> &'static tokio::sync::Mutex<Option<tokio::sync::oneshot::Sender<()>>> {
    CALLBACK_ABORT.get_or_init(|| tokio::sync::Mutex::new(None))
}

#[derive(serde::Deserialize, Default)]
struct OAuthMetadata {
    authorization_endpoint: Option<String>,
    token_endpoint: Option<String>,
    registration_endpoint: Option<String>,
}

async fn discover_oauth_metadata(server_url: &str) -> OAuthMetadata {
    let base = server_url.trim_end_matches('/');
    let origin = reqwest::Url::parse(base)
        .ok()
        .map(|u| format!("{}://{}", u.scheme(), u.host_str().unwrap_or("")))
        .unwrap_or_else(|| base.to_string());

    let client = reqwest::Client::builder()
        .user_agent("UnifiedDev/1.0")
        .build()
        .unwrap_or_default();

    for path in &[
        "/.well-known/oauth-authorization-server",
        "/.well-known/openid-configuration",
    ] {
        let url = format!("{origin}{path}");
        if let Ok(resp) = client.get(&url).send().await {
            if resp.status().is_success() {
                if let Ok(meta) = resp.json::<OAuthMetadata>().await {
                    return meta;
                }
            }
        }
    }

    OAuthMetadata::default()
}

async fn dynamic_client_registration(registration_endpoint: &str, redirect_uri: &str) -> Option<String> {
    #[derive(serde::Serialize)]
    struct RegistrationRequest<'a> {
        client_name: &'a str,
        redirect_uris: Vec<&'a str>,
        grant_types: Vec<&'a str>,
        response_types: Vec<&'a str>,
        token_endpoint_auth_method: &'a str,
    }

    #[derive(serde::Deserialize)]
    struct RegistrationResponse {
        client_id: String,
    }

    let client = reqwest::Client::builder()
        .user_agent("UnifiedDev/1.0")
        .build()
        .ok()?;

    let resp = client
        .post(registration_endpoint)
        .json(&RegistrationRequest {
            client_name: "Unified Dev",
            redirect_uris: vec![redirect_uri],
            grant_types: vec!["authorization_code"],
            response_types: vec!["code"],
            token_endpoint_auth_method: "none",
        })
        .send()
        .await
        .ok()?;

    resp.json::<RegistrationResponse>().await.ok().map(|r| r.client_id)
}

pub struct OAuthFlowResult {
    pub access_token: String,
    pub token_type: String,
}

pub async fn connect(server_url: &str, app: &AppHandle) -> AppResult<OAuthFlowResult> {
    use tokio::io::{AsyncReadExt, AsyncWriteExt};

    if let Some(sender) = callback_abort().lock().await.take() {
        let _ = sender.send(());
        tokio::time::sleep(std::time::Duration::from_millis(150)).await;
    }

    let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
        .await
        .map_err(|e| AppError::Internal(format!("Failed to bind MCP callback listener: {e}")))?;

    let port = listener.local_addr()?.port();
    let redirect_uri = format!("http://localhost:{port}/callback");

    let meta = discover_oauth_metadata(server_url).await;

    let base = server_url.trim_end_matches('/');
    let origin = reqwest::Url::parse(base)
        .ok()
        .map(|u| format!("{}://{}", u.scheme(), u.host_str().unwrap_or("")))
        .unwrap_or_else(|| base.to_string());

    let auth_endpoint = meta
        .authorization_endpoint
        .unwrap_or_else(|| format!("{origin}/oauth/authorize"));

    let token_endpoint = meta
        .token_endpoint
        .unwrap_or_else(|| format!("{origin}/oauth/token"));

    let client_id = if let Some(reg) = meta.registration_endpoint {
        dynamic_client_registration(&reg, &redirect_uri)
            .await
            .unwrap_or_else(|| "unified-dev".to_string())
    } else {
        "unified-dev".to_string()
    };

    let state = uuid::Uuid::new_v4().to_string();
    let (code_verifier, code_challenge) = generate_pkce();

    let auth_url = reqwest::Url::parse_with_params(
        &auth_endpoint,
        &[
            ("response_type", "code"),
            ("client_id", &client_id),
            ("redirect_uri", &redirect_uri),
            ("state", &state),
            ("scope", "read write"),
            ("code_challenge", &code_challenge),
            ("code_challenge_method", &"S256".to_string()),
        ],
    )
    .map(|u| u.to_string())
    .unwrap_or_else(|_| format!(
        "{auth_endpoint}?response_type=code&client_id={client_id}&redirect_uri={redirect_uri}&state={state}&scope=read+write&code_challenge={code_challenge}&code_challenge_method=S256"
    ));

    app.opener()
        .open_url(&auth_url, None::<&str>)
        .map_err(|e| AppError::Internal(format!("Failed to open browser: {e}")))?;

    let (cancel_tx, mut cancel_rx) = tokio::sync::oneshot::channel();
    *callback_abort().lock().await = Some(cancel_tx);

    let accept_result = tokio::select! {
        result = tokio::time::timeout(std::time::Duration::from_secs(300), listener.accept()) => {
            result.map_err(|_| AppError::Internal("MCP OAuth callback timed out".to_string()))?
        }
        _ = &mut cancel_rx => {
            return Err(AppError::Internal("MCP OAuth callback cancelled".to_string()));
        }
    };

    *callback_abort().lock().await = None;

    let (mut stream, _) = accept_result?;

    let mut buf = vec![0u8; 4096];
    let n = tokio::time::timeout(std::time::Duration::from_secs(15), stream.read(&mut buf))
        .await
        .map_err(|_| AppError::Internal("MCP OAuth callback read timed out".to_string()))??;

    let request = String::from_utf8_lossy(&buf[..n]);
    let path = request
        .lines()
        .next()
        .and_then(|line| line.split_whitespace().nth(1))
        .ok_or_else(|| AppError::Internal("MCP callback: missing path".to_string()))?;

    let callback_url = reqwest::Url::parse(&format!("http://localhost{path}"))
        .map_err(|e| AppError::Internal(format!("MCP callback: invalid URL: {e}")))?;

    let code = callback_url
        .query_pairs()
        .find(|(k, _)| k == "code")
        .map(|(_, v)| v.into_owned())
        .ok_or_else(|| AppError::Internal("MCP callback: missing 'code'".to_string()))?;

    let returned_state = callback_url
        .query_pairs()
        .find(|(k, _)| k == "state")
        .map(|(_, v)| v.into_owned())
        .ok_or_else(|| AppError::Internal("MCP callback: missing 'state'".to_string()))?;

    if returned_state != state {
        return Err(AppError::Internal("MCP callback: state mismatch".to_string()));
    }

    let html = "<html><body><h2>Connected! You can close this tab.</h2></body></html>";
    let http_response = format!(
        "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
        html.len(),
        html
    );
    stream.write_all(http_response.as_bytes()).await?;
    drop(stream);

    #[derive(serde::Serialize)]
    struct TokenRequest<'a> {
        grant_type: &'a str,
        code: &'a str,
        redirect_uri: &'a str,
        client_id: &'a str,
        code_verifier: &'a str,
    }

    #[derive(serde::Deserialize)]
    struct TokenResponse {
        access_token: String,
        #[serde(default = "default_token_type")]
        token_type: String,
    }

    fn default_token_type() -> String {
        "bearer".to_string()
    }

    let http = reqwest::Client::builder()
        .user_agent("UnifiedDev/1.0")
        .build()
        .map_err(|e| AppError::Internal(e.to_string()))?;

    let token_resp = http
        .post(&token_endpoint)
        .form(&TokenRequest {
            grant_type: "authorization_code",
            code: &code,
            redirect_uri: &redirect_uri,
            client_id: &client_id,
            code_verifier: &code_verifier,
        })
        .send()
        .await
        .map_err(|e| AppError::Internal(format!("MCP token exchange failed: {e}")))?;

    if !token_resp.status().is_success() {
        let status = token_resp.status();
        let body = token_resp.text().await.unwrap_or_default();
        return Err(AppError::Internal(format!("MCP token exchange error {status}: {body}")));
    }

    let token: TokenResponse = token_resp
        .json()
        .await
        .map_err(|e| AppError::Internal(format!("MCP token parse error: {e}")))?;

    Ok(OAuthFlowResult {
        access_token: token.access_token,
        token_type: token.token_type,
    })
}

pub async fn cancel() {
    if let Some(sender) = callback_abort().lock().await.take() {
        let _ = sender.send(());
    }
}
