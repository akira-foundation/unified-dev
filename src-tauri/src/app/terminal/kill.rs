use std::sync::{Arc, Mutex};

use tauri::State;

use crate::app::terminal::state::TerminalState;

pub fn kill(
    manager: State<'_, Arc<Mutex<TerminalState>>>,
    session_id: String,
) -> Result<(), String> {
    let mut mgr = manager.lock().map_err(|e| format!("Lock error: {e}"))?;
    mgr.kill(&session_id)
}
