use std::sync::{Arc, Mutex};

use tauri::State;

use crate::app::terminal::state::TerminalState;

pub fn resize(
    manager: State<'_, Arc<Mutex<TerminalState>>>,
    session_id: String,
    cols: u16,
    rows: u16,
) -> Result<(), String> {
    let mgr = manager.lock().map_err(|e| format!("Lock error: {e}"))?;
    mgr.resize(&session_id, cols, rows)
}
