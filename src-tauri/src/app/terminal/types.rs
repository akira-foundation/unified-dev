use serde::Serialize;

#[derive(Clone, Serialize)]
pub struct TerminalOutput {
    pub session_id: String,
    pub data: Vec<u8>,
}
