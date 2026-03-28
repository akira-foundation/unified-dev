use tauri::State;

use crate::providers::drivers::github::oauth;
use crate::state::AppState;

pub async fn install_github_app(_state: State<'_, AppState>, app: tauri::AppHandle) -> Result<(), String> {
    use tauri_plugin_opener::OpenerExt;

    let app_slug = option_env!("GITHUB_APP_SLUG").unwrap_or("akira-apps-unified-dev");
    let oauth_state = uuid::Uuid::new_v4().to_string();

    let listener = oauth::bind_callback_listener()
        .await
        .map_err(|e| e.to_string())?;

    let install_url = format!(
        "https://github.com/apps/{app_slug}/installations/select_target?state={oauth_state}"
    );

    app.opener()
        .open_url(&install_url, None::<&str>)
        .map_err(|e| format!("Failed to open browser: {e}"))?;

    let _ = oauth::await_callback(listener, &oauth_state)
        .await
        .map_err(|e| e.to_string())?;

    Ok(())
}
