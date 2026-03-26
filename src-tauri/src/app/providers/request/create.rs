use serde::{Deserialize, Serialize};

use crate::providers::enums::ProviderAuth;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateProviderRequest {
    pub name: String,
    pub kind: String,
    pub auth: ProviderAuth,
    #[serde(default)]
    pub account_login: Option<String>,
    #[serde(default)]
    pub account_type: Option<String>,
}
