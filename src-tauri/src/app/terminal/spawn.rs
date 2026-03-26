use std::io::Read;
use std::sync::{Arc, Mutex};

use tauri::{AppHandle, Emitter, State};

use crate::app::terminal::state::TerminalState;
use crate::app::terminal::types::TerminalOutput;

pub async fn spawn(
    app: AppHandle,
    manager: State<'_, Arc<Mutex<TerminalState>>>,
    cwd: Option<String>,
    cols: Option<u16>,
    rows: Option<u16>,
) -> Result<String, String> {
    let session_id = uuid::Uuid::new_v4().to_string();
    let c = cols.unwrap_or(120);
    let r = rows.unwrap_or(30);

    {
        let mut mgr = manager.lock().map_err(|e| format!("Lock error: {e}"))?;
        mgr.spawn(session_id.clone(), cwd, c, r)?;
    }

    let reader = {
        let mgr = manager.lock().map_err(|e| format!("Lock error: {e}"))?;
        mgr.get_reader(&session_id)?
    };

    let sid = session_id.clone();
    std::thread::spawn(move || {
        stream_output(app, sid, reader);
    });

    Ok(session_id)
}

fn stream_output(app: AppHandle, session_id: String, mut reader: Box<dyn Read + Send>) {
    let mut buf = [0u8; 4096];
    loop {
        match reader.read(&mut buf) {
            Ok(0) => break,
            Ok(n) => {
                let _ = app.emit(
                    "terminal-output",
                    TerminalOutput {
                        session_id: session_id.clone(),
                        data: buf[..n].to_vec(),
                    },
                );
            }
            Err(_) => break,
        }
    }
}
