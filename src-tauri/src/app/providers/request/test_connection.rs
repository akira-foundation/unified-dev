use serde::{Deserialize, Serialize};

use crate::providers::enums::ProviderAuth;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TestProviderConnectionRequest {
    pub kind: String,
    pub auth: ProviderAuth,
}
