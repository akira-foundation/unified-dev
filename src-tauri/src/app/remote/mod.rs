use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::{Arc, Mutex, OnceLock};

use axum::routing::{get, post};
use axum::Router;
use tauri::AppHandle;
use tokio::sync::oneshot;
use tokio::task::JoinHandle;

use crate::app::settings::remote::RemoteSettingsDto;
use crate::app::support::error::{AppError, AppResult};

mod abort_thread;
mod get_changes;
mod get_messages;
mod get_pr;
mod health;
mod list_repositories;
mod pair;
mod send_message;
pub mod state;
mod support;
pub mod types;

use state::RemoteHostState;

struct RemoteHostRuntime {
    shutdown: Option<oneshot::Sender<()>>,
    task: JoinHandle<()>,
}

static REMOTE_HOST_RUNTIME: OnceLock<Mutex<Option<RemoteHostRuntime>>> = OnceLock::new();

pub async fn start(
    settings: &RemoteSettingsDto,
    db_pool: sqlx::SqlitePool,
    abort_handles: Arc<Mutex<HashMap<String, JoinHandle<()>>>>,
    app: AppHandle,
) -> AppResult<()> {
    stop().await?;

    let addr: SocketAddr = format!("{}:{}", settings.bind_address, settings.port)
        .parse()
        .map_err(|error| AppError::Internal(format!("Invalid remote bind address: {error}")))?;

    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .map_err(|error| AppError::Internal(format!("Failed to bind remote host: {error}")))?;

    let state = RemoteHostState { db_pool, abort_handles, app };
    let router = Router::new()
        .route("/remote/health", get(health::health))
        .route("/remote/auth/pair", post(pair::pair))
        .route("/remote/repositories", get(list_repositories::list_repositories))
        .route("/remote/threads/{thread_id}/messages", get(get_messages::get_messages).post(send_message::send_message))
        .route("/remote/threads/{thread_id}/abort", post(abort_thread::abort_thread))
        .route("/remote/threads/{thread_id}/changes", get(get_changes::get_changes))
        .route("/remote/threads/{thread_id}/pr", get(get_pr::get_pr))
        .with_state(state);

    let (shutdown_tx, shutdown_rx) = oneshot::channel::<()>();
    let task = tokio::spawn(async move {
        let _ = axum::serve(listener, router)
            .with_graceful_shutdown(async {
                let _ = shutdown_rx.await;
            })
            .await;
    });

    let runtime = REMOTE_HOST_RUNTIME.get_or_init(|| Mutex::new(None));
    if let Ok(mut guard) = runtime.lock() {
        *guard = Some(RemoteHostRuntime {
            shutdown: Some(shutdown_tx),
            task,
        });
    }

    Ok(())
}

pub async fn stop() -> AppResult<()> {
    let runtime = REMOTE_HOST_RUNTIME.get_or_init(|| Mutex::new(None));
    if let Ok(mut guard) = runtime.lock() {
        if let Some(mut runtime) = guard.take() {
            if let Some(shutdown) = runtime.shutdown.take() {
                let _ = shutdown.send(());
            }
            runtime.task.abort();
        }
    }
    Ok(())
}
