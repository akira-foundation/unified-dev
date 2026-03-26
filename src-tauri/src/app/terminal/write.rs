use std::sync::{Arc, Mutex};

use tauri::State;

use crate::app::terminal::state::TerminalState;

pub fn write(
    manager: State<'_, Arc<Mutex<TerminalState>>>,
    session_id: String,
    data: Vec<u8>,
) -> Result<(), String> {
    let mgr = manager.lock().map_err(|e| format!("Lock error: {e}"))?;
    mgr.write(&session_id, &data)
}
