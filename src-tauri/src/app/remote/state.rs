use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use tauri::AppHandle;
use tokio::task::JoinHandle;

#[derive(Clone)]
pub struct RemoteHostState {
    pub db_pool: sqlx::SqlitePool,
    pub abort_handles: Arc<Mutex<HashMap<String, JoinHandle<()>>>>,
    pub app: AppHandle,
}
