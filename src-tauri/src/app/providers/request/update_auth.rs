use serde::{Deserialize, Serialize};

use crate::providers::enums::ProviderAuth;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UpdateProviderAuthRequest {
    pub provider_id: String,
    pub auth: ProviderAuth,
}
