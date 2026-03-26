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
    aborted: bool,
}

#[derive(Debug, Serialize, Clone)]
struct StreamErrorPayload<'a> {
    thread_id: &'a str,
    error: &'a str,
}

#[derive(Debug, Serialize, Clone)]
pub struct StreamToolCallPayload {
    pub thread_id: String,
    pub label: String,
    pub status: String,
    pub output: Option<String>,
}

pub fn emit_token(app: &AppHandle, thread_id: &str, token: &str) {
    let _ = app.emit(
        "agent-stream-token",
        StreamTokenPayload { thread_id, token },
    );
}

pub fn emit_done(app: &AppHandle, thread_id: &str) {
    let _ = app.emit(
        "agent-stream-done",
        StreamDonePayload {
            thread_id,
            aborted: false,
        },
    );
}

pub fn emit_done_aborted(app: &AppHandle, thread_id: &str) {
    let _ = app.emit(
        "agent-stream-done",
        StreamDonePayload {
            thread_id,
            aborted: true,
        },
    );
}

pub fn emit_error(app: &AppHandle, thread_id: &str, error: &str) {
    let _ = app.emit(
        "agent-stream-error",
        StreamErrorPayload { thread_id, error },
    );
}

pub fn emit_tool_call(app: &AppHandle, payload: StreamToolCallPayload) {
    let _ = app.emit("agent-stream-tool-call", payload);
}
