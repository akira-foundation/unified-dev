use crate::app::support::error::{AppError, AppResult};
use std::sync::OnceLock;

static CALLBACK_ABORT: OnceLock<tokio::sync::Mutex<Option<tokio::sync::oneshot::Sender<()>>>> = OnceLock::new();

fn callback_abort() -> &'static tokio::sync::Mutex<Option<tokio::sync::oneshot::Sender<()>>> {
    CALLBACK_ABORT.get_or_init(|| tokio::sync::Mutex::new(None))
}

pub async fn bind_callback_listener() -> AppResult<tokio::net::TcpListener> {
    if let Some(sender) = callback_abort().lock().await.take() {
        let _ = sender.send(());
        tokio::time::sleep(std::time::Duration::from_millis(150)).await;
    }

    tokio::net::TcpListener::bind("127.0.0.1:4567")
        .await
        .map_err(|e| AppError::Provider(format!("Failed to bind callback listener: {e}")))
}

pub async fn await_callback(listener: tokio::net::TcpListener, expected_state: &str) -> AppResult<String> {
    use tokio::io::{AsyncReadExt, AsyncWriteExt};

    let (cancel_tx, mut cancel_rx) = tokio::sync::oneshot::channel();
    *callback_abort().lock().await = Some(cancel_tx);

    let accept_result = tokio::select! {
        result = tokio::time::timeout(std::time::Duration::from_secs(300), listener.accept()) => {
            result.map_err(|_| AppError::Provider("GitHub callback timed out".to_string()))?
        }
        _ = &mut cancel_rx => {
            return Err(AppError::Provider("GitHub callback cancelled".to_string()));
        }
    };

    *callback_abort().lock().await = None;

    let (mut stream, _) = accept_result?;

    let mut buf = vec![0u8; 4096];
    let n = tokio::time::timeout(std::time::Duration::from_secs(15), stream.read(&mut buf))
        .await
        .map_err(|_| AppError::Provider("GitHub callback read timed out".to_string()))??;
    let request = String::from_utf8_lossy(&buf[..n]);

    let path = request
        .lines()
        .next()
        .and_then(|line| line.split_whitespace().nth(1))
        .ok_or_else(|| AppError::Provider("path not found in GitHub callback".to_string()))?;

    let callback_url = format!("http://localhost{path}");
    let url = reqwest::Url::parse(&callback_url)
        .map_err(|e| AppError::Provider(format!("invalid GitHub callback url: {e}")))?;

    let code = url
        .query_pairs()
        .find(|(key, _)| key == "code")
        .map(|(_, value)| value.into_owned())
        .ok_or_else(|| AppError::Provider("code not found in GitHub callback".to_string()))?;

    let state = url
        .query_pairs()
        .find(|(key, _)| key == "state")
        .map(|(_, value)| value.into_owned())
        .ok_or_else(|| AppError::Provider("state not found in GitHub callback".to_string()))?;

    if state != expected_state {
        return Err(AppError::Provider("GitHub callback state mismatch".to_string()));
    }

    let body = "<html><body><h2>Connected! You can close this tab.</h2></body></html>";
    let response = format!(
        "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
        body.len(),
        body
    );
    stream.write_all(response.as_bytes()).await?;

    Ok(code)
}
