use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PairResponse {
    pub access_token: String,
    pub device_id: String,
    pub host_name: String,
    pub host_fingerprint: String,
}

#[derive(Debug, Deserialize)]
pub struct PairRequest {
    pub pairing_code: String,
    pub device_name: String,
    pub device_fingerprint: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct RemoteSendMessageRequest {
    pub content: String,
    pub model: String,
    pub plan_mode: Option<bool>,
    pub thinking_budget: Option<String>,
    pub fast_mode: Option<bool>,
}

#[derive(Debug, Serialize)]
pub struct AcceptedResponse {
    pub accepted: bool,
}
