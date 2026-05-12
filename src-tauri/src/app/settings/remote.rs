use rand::{distr::Alphanumeric, Rng};
use tauri::{AppHandle, State};

use crate::app::support::error::AppResult;
use crate::state::AppState;

const REMOTE_SETTINGS_ID: &str = "remote";

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteDeviceDto {
    pub id: String,
    pub name: String,
    pub last_seen: String,
    pub status: String,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteSettingsDto {
    pub enabled: bool,
    pub host_name: String,
    pub host_fingerprint: String,
    pub bind_address: String,
    pub port: i64,
    pub tailscale_required: bool,
    pub pairing_code: String,
    pub pairing_code_expires_at: String,
    pub devices: Vec<RemoteDeviceDto>,
}

fn default_host_name() -> String {
    std::env::var("HOSTNAME")
        .or_else(|_| std::env::var("COMPUTERNAME"))
        .ok()
        .filter(|value| !value.trim().is_empty())
        .unwrap_or_else(|| "localhost.local".to_string())
}

fn random_code(prefix: &str, len: usize) -> String {
    let suffix: String = rand::rng()
        .sample_iter(Alphanumeric)
        .take(len)
        .map(char::from)
        .collect::<String>()
        .to_uppercase();

    format!("{prefix}{suffix}")
}

async fn ensure_settings_row(state: &AppState) -> AppResult<()> {
    let existing = sqlx::query_scalar::<_, String>(
        "SELECT id FROM remote_settings WHERE id = ? LIMIT 1",
    )
    .bind(REMOTE_SETTINGS_ID)
    .fetch_optional(&state.db_pool)
    .await?;

    if existing.is_some() {
        return Ok(());
    }

    let now = chrono::Utc::now().to_rfc3339();
    let expires = (chrono::Utc::now() + chrono::Duration::minutes(10)).to_rfc3339();

    sqlx::query(
        "INSERT INTO remote_settings (id, enabled, host_name, host_fingerprint, bind_address, port, tailscale_required, pairing_code, pairing_code_expires_at, updated_at)
         VALUES (?, 0, ?, ?, '127.0.0.1', 4280, 1, ?, ?, ?)",
    )
    .bind(REMOTE_SETTINGS_ID)
    .bind(default_host_name())
    .bind(random_code("host-", 10))
    .bind(random_code("UNFD-", 4))
    .bind(expires)
    .bind(now)
    .execute(&state.db_pool)
    .await?;

    Ok(())
}

pub async fn get(state: State<'_, AppState>) -> AppResult<RemoteSettingsDto> {
    ensure_settings_row(&state).await?;

    let (enabled, host_name, host_fingerprint, bind_address, port, tailscale_required, pairing_code, pairing_code_expires_at) =
        sqlx::query_as::<_, (i64, String, String, String, i64, i64, String, String)>(
            "SELECT enabled, host_name, host_fingerprint, bind_address, port, tailscale_required, pairing_code, pairing_code_expires_at FROM remote_settings WHERE id = ? LIMIT 1",
        )
        .bind(REMOTE_SETTINGS_ID)
        .fetch_one(&state.db_pool)
        .await?;

    let devices = sqlx::query_as::<_, (String, String, Option<String>, Option<String>)>(
        "SELECT id, name, last_seen_at, revoked_at FROM remote_devices ORDER BY created_at DESC",
    )
    .fetch_all(&state.db_pool)
    .await?
    .into_iter()
    .filter(|(_, _, _, revoked_at)| revoked_at.is_none())
    .map(|(id, name, last_seen_at, _)| {
        let status = if last_seen_at.is_some() {
            "connected".to_string()
        } else {
            "idle".to_string()
        };

        RemoteDeviceDto {
            id,
            name,
            last_seen: last_seen_at.unwrap_or_else(|| "never".to_string()),
            status,
        }
    })
    .collect();

    Ok(RemoteSettingsDto {
        enabled: enabled != 0,
        host_name,
        host_fingerprint,
        bind_address,
        port,
        tailscale_required: tailscale_required != 0,
        pairing_code,
        pairing_code_expires_at,
        devices,
    })
}

pub async fn set_enabled(enabled: bool, state: State<'_, AppState>, app: AppHandle) -> AppResult<RemoteSettingsDto> {
    ensure_settings_row(&state).await?;

    sqlx::query("UPDATE remote_settings SET enabled = ?, updated_at = ? WHERE id = ?")
        .bind(enabled as i64)
        .bind(chrono::Utc::now().to_rfc3339())
        .bind(REMOTE_SETTINGS_ID)
        .execute(&state.db_pool)
        .await?;

    let settings = get(state.clone()).await?;

    if enabled {
        crate::app::remote::start(
            &settings,
            state.db_pool.clone(),
            state.abort_handles.clone(),
            app,
        ).await?;
    } else {
        crate::app::remote::stop().await?;
    }

    Ok(settings)
}

pub async fn regenerate_pairing_code(state: State<'_, AppState>) -> AppResult<RemoteSettingsDto> {
    ensure_settings_row(&state).await?;

    sqlx::query(
        "UPDATE remote_settings SET pairing_code = ?, pairing_code_expires_at = ?, updated_at = ? WHERE id = ?",
    )
    .bind(random_code("UNFD-", 4))
    .bind((chrono::Utc::now() + chrono::Duration::minutes(10)).to_rfc3339())
    .bind(chrono::Utc::now().to_rfc3339())
    .bind(REMOTE_SETTINGS_ID)
    .execute(&state.db_pool)
    .await?;

    get(state).await
}

pub async fn revoke_device(device_id: String, state: State<'_, AppState>) -> AppResult<RemoteSettingsDto> {
    ensure_settings_row(&state).await?;

    sqlx::query("UPDATE remote_devices SET revoked_at = ?, last_seen_at = COALESCE(last_seen_at, ?) WHERE id = ?")
        .bind(chrono::Utc::now().to_rfc3339())
        .bind(chrono::Utc::now().to_rfc3339())
        .bind(device_id)
        .execute(&state.db_pool)
        .await?;

    get(state).await
}
