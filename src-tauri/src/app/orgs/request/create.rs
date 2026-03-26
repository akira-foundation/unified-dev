use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateOrgRequest {
    pub name: String,
    pub provider_id: String,
    pub external_id: Option<String>,
}
