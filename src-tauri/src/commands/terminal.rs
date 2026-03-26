use std::sync::{Arc, Mutex};

use tauri::{AppHandle, State};

use crate::app::terminal;
use crate::app::terminal::state::TerminalState;

#[tauri::command]
pub async fn terminal_spawn(
    app: AppHandle,
    manager: State<'_, Arc<Mutex<TerminalState>>>,
    cwd: Option<String>,
    cols: Option<u16>,
    rows: Option<u16>,
) -> Result<String, String> {
    terminal::spawn::spawn(app, manager, cwd, cols, rows).await
}

#[tauri::command]
pub fn terminal_write(
    manager: State<'_, Arc<Mutex<TerminalState>>>,
    session_id: String,
    data: Vec<u8>,
) -> Result<(), String> {
    terminal::write::write(manager, session_id, data)
}

#[tauri::command]
pub fn terminal_resize(
    manager: State<'_, Arc<Mutex<TerminalState>>>,
    session_id: String,
    cols: u16,
    rows: u16,
) -> Result<(), String> {
    terminal::resize::resize(manager, session_id, cols, rows)
}

#[tauri::command]
pub fn terminal_kill(
    manager: State<'_, Arc<Mutex<TerminalState>>>,
    session_id: String,
) -> Result<(), String> {
    terminal::kill::kill(manager, session_id)
}
