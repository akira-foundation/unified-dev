use axum::http::{HeaderMap, StatusCode};
use rand::Rng;

pub async fn authorize(headers: &HeaderMap, pool: &sqlx::SqlitePool) -> Result<(), (StatusCode, String)> {
    let token = headers
        .get(axum::http::header::AUTHORIZATION)
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.strip_prefix("Bearer "))
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| (StatusCode::UNAUTHORIZED, "Missing bearer token".to_string()))?;

    let device_id = sqlx::query_scalar::<_, Option<String>>(
        "SELECT id FROM remote_devices WHERE token_hash = ? AND revoked_at IS NULL LIMIT 1",
    )
    .bind(token)
    .fetch_one(pool)
    .await
    .map_err(internal_error)?;

    if let Some(device_id) = device_id {
        sqlx::query("UPDATE remote_devices SET last_seen_at = ? WHERE id = ?")
            .bind(chrono::Utc::now().to_rfc3339())
            .bind(device_id)
            .execute(pool)
            .await
            .map_err(internal_error)?;
        Ok(())
    } else {
        Err((StatusCode::UNAUTHORIZED, "Invalid bearer token".to_string()))
    }
}

pub async fn thread_workspace_path(pool: &sqlx::SqlitePool, thread_id: &str) -> Result<String, (StatusCode, String)> {
    sqlx::query_scalar::<_, Option<String>>(
        "SELECT workspace_path FROM threads WHERE id = ? LIMIT 1",
    )
    .bind(thread_id)
    .fetch_one(pool)
    .await
    .map_err(internal_error)?
    .ok_or_else(|| (StatusCode::NOT_FOUND, "Thread not found".to_string()))
}

pub fn internal_error(error: impl ToString) -> (StatusCode, String) {
    (StatusCode::INTERNAL_SERVER_ERROR, error.to_string())
}

pub fn random_token() -> String {
    rand::rng()
        .sample_iter(&rand::distr::Alphanumeric)
        .take(48)
        .map(char::from)
        .collect()
}
