use std::collections::HashMap;
use std::io::{Read, Write};
use std::sync::{Arc, Mutex};

use portable_pty::{native_pty_system, CommandBuilder, MasterPty, PtySize};

pub struct PtySession {
    master: Box<dyn MasterPty + Send>,
    writer: Box<dyn Write + Send>,
    _child: Box<dyn portable_pty::Child + Send + Sync>,
}

pub struct TerminalState {
    sessions: HashMap<String, Arc<Mutex<PtySession>>>,
}

impl TerminalState {
    pub fn new() -> Self {
        Self {
            sessions: HashMap::new(),
        }
    }

    pub fn spawn(
        &mut self,
        session_id: String,
        cwd: Option<String>,
        cols: u16,
        rows: u16,
    ) -> Result<(), String> {
        let pty_system = native_pty_system();
        let size = PtySize {
            rows,
            cols,
            pixel_width: 0,
            pixel_height: 0,
        };

        let pair = pty_system
            .openpty(size)
            .map_err(|e| format!("Failed to open PTY: {e}"))?;

        let shell = std::env::var("SHELL").unwrap_or_else(|_| "/bin/zsh".to_string());
        let mut cmd = CommandBuilder::new(&shell);
        cmd.arg("-l");
        cmd.env("TERM", "xterm-256color");
        cmd.env("COLORTERM", "truecolor");

        if let Some(dir) = cwd {
            cmd.cwd(dir);
        }

        let child = pair
            .slave
            .spawn_command(cmd)
            .map_err(|e| format!("Failed to spawn shell: {e}"))?;

        let writer = pair
            .master
            .take_writer()
            .map_err(|e| format!("Failed to get PTY writer: {e}"))?;

        let session = PtySession {
            master: pair.master,
            writer,
            _child: child,
        };

        self.sessions
            .insert(session_id.clone(), Arc::new(Mutex::new(session)));

        Ok(())
    }

    pub fn get_reader(&self, session_id: &str) -> Result<Box<dyn Read + Send>, String> {
        let session = self
            .sessions
            .get(session_id)
            .ok_or_else(|| format!("Session not found: {session_id}"))?;

        let guard = session.lock().map_err(|e| format!("Lock error: {e}"))?;
        guard
            .master
            .try_clone_reader()
            .map_err(|e| format!("Failed to clone reader: {e}"))
    }

    pub fn write(&self, session_id: &str, data: &[u8]) -> Result<(), String> {
        let session = self
            .sessions
            .get(session_id)
            .ok_or_else(|| format!("Session not found: {session_id}"))?;

        let mut guard = session.lock().map_err(|e| format!("Lock error: {e}"))?;
        guard
            .writer
            .write_all(data)
            .map_err(|e| format!("Write error: {e}"))
    }

    pub fn resize(&self, session_id: &str, cols: u16, rows: u16) -> Result<(), String> {
        let session = self
            .sessions
            .get(session_id)
            .ok_or_else(|| format!("Session not found: {session_id}"))?;

        let guard = session.lock().map_err(|e| format!("Lock error: {e}"))?;
        guard
            .master
            .resize(PtySize {
                rows,
                cols,
                pixel_width: 0,
                pixel_height: 0,
            })
            .map_err(|e| format!("Resize error: {e}"))
    }

    pub fn kill(&mut self, session_id: &str) -> Result<(), String> {
        self.sessions
            .remove(session_id)
            .ok_or_else(|| format!("Session not found: {session_id}"))?;
        Ok(())
    }
}
