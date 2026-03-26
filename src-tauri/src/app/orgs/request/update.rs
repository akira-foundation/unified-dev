use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UpdateOrgRequest {
    pub id: String,
    pub name: String,
    pub provider_id: Option<String>,
}
