use crate::support::error::{AppError, AppResult};

pub struct ConnectResult {
    pub access_token: String,
    pub refresh_token: Option<String>,
    pub expires_at: Option<i64>,
    pub account_login: String,
    pub account_type: String,
}

pub async fn exchange_code(api_url: &str, code: &str) -> AppResult<ConnectResult> {
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

pub async fn await_callback(listener: tokio::net::TcpListener) -> AppResult<String> {
    use tokio::io::{AsyncReadExt, AsyncWriteExt};

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
