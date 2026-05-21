use std::sync::Arc;

use tauri::{Emitter, Listener, Manager};

use crate::app::support::error::AppResult;
use crate::app::support::security::{KeyStore, TokenCipher};
use crate::app::terminal::state::TerminalState;
use crate::providers::default_registry;
use crate::state::AppState;
use crate::{app, database};

pub fn init(app: &mut tauri::App) -> Result<(), Box<dyn std::error::Error>> {
    let setup_result: AppResult<()> = tauri::async_runtime::block_on(async {
        let pool = database::init_pool(app.handle()).await?;
        let key = KeyStore::load_or_create_key(app.handle())?;
        let cipher = Arc::new(TokenCipher::new(key));

        let provider_factory = Arc::new(default_registry()?);

        app.manage(AppState::new(provider_factory, cipher, pool.clone()));

        {
            let app_state = app.state::<AppState>();
            if let Some(token) = app::license::load_customer_token(&app_state.db_pool, &app_state.token_cipher).await? {
                let mut billing = app_state.billing.write().await;
                billing.set_customer_token(token);
            }
        }

        let app_state = app.state::<AppState>();
        if let Ok(remote_settings) = app::settings::remote::get(app_state).await {
            if remote_settings.enabled {
                let app_state = app.state::<AppState>();
                let _ = app::remote::start(
                    &remote_settings,
                    app_state.db_pool.clone(),
                    app_state.abort_handles.clone(),
                    app.handle().clone(),
                ).await;
            }
        }

        let terminal_manager = Arc::new(std::sync::Mutex::new(TerminalState::new()));
        app.manage(terminal_manager);

        app::settings::poller::start(app.handle().clone());

        {
            let app_state = app.state::<AppState>();
            app::notifications::refresh_badge(app.handle(), &app_state.db_pool).await;
        }

        Ok(())
    });

    setup_result.map_err(|error| Box::new(error) as Box<dyn std::error::Error>)?;

    let app_handle = app.handle().clone();
    app.listen("deep-link://new-url", move |event: tauri::Event| {
        if let Ok(urls) = serde_json::from_str::<Vec<String>>(event.payload()) {
            for url in urls {
                if let Ok(parsed) = reqwest::Url::parse(&url) {
                    if parsed.scheme() == "akira" && parsed.path() == "/license/activate" {
                        if let Some(session_id) = parsed.query_pairs().find(|(k, _)| k == "session_id").map(|(_, v): (_, std::borrow::Cow<str>)| v.into_owned()) {
                            let _ = app_handle.emit("license://activate", session_id);
                        }
                    }
                }
            }
        }
    });

    Ok(())
}
