use serde::Serialize;
use tauri::{AppHandle, Emitter};

#[derive(Debug, Serialize, Clone)]
struct StreamTokenPayload<'a> {
    thread_id: &'a str,
    token: &'a str,
}

#[derive(Debug, Serialize, Clone)]
struct StreamDonePayload<'a> {
    thread_id: &'a str,
}

#[derive(Debug, Serialize, Clone)]
struct StreamErrorPayload<'a> {
    thread_id: &'a str,
    error: &'a str,
}

#[derive(Debug, Serialize, Clone)]
pub struct StreamToolCallPayload {
    pub thread_id: String,
    /// Short human-readable label, e.g. "read_file: src/helpers.php"
    pub label: String,
    /// "running" | "done" | "error"
    pub status: String,
    /// The tool output (populated when status == "done" or "error")
    pub output: Option<String>,
}

/// Emits a partial token chunk to the frontend.
pub fn emit_token(app: &AppHandle, thread_id: &str, token: &str) {
    let _ = app.emit(
        "agent-stream-token",
        StreamTokenPayload { thread_id, token },
    );
}

/// Signals that the stream has completed successfully.
pub fn emit_done(app: &AppHandle, thread_id: &str) {
    let _ = app.emit("agent-stream-done", StreamDonePayload { thread_id });
}

/// Signals that the stream encountered an error.
pub fn emit_error(app: &AppHandle, thread_id: &str, error: &str) {
    let _ = app.emit(
        "agent-stream-error",
        StreamErrorPayload { thread_id, error },
    );
}

/// Signals a tool call event (running / done / error) to the frontend.
pub fn emit_tool_call(app: &AppHandle, payload: StreamToolCallPayload) {
    let _ = app.emit("agent-stream-tool-call", payload);
}
