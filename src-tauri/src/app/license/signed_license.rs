use std::collections::HashMap;

use base64::Engine;
use ed25519_dalek::{Signature, Verifier, VerifyingKey};
use serde::Deserialize;

use crate::app::support::error::{AppError, AppResult};

const AKIRA_LICENSE_PUBKEY: &str = env!("AKIRA_LICENSE_PUBKEY");

#[derive(Debug, Clone)]
pub struct Keyring {
    keys: HashMap<String, VerifyingKey>,
}

impl Keyring {
    pub fn from_build_env() -> AppResult<Self> {
        let raw = AKIRA_LICENSE_PUBKEY.trim();
        if raw.is_empty() {
            return Err(AppError::Internal(
                "AKIRA_LICENSE_PUBKEY is empty; cannot verify licenses".into(),
            ));
        }

        let mut keys = HashMap::new();
        for entry in raw.split(',') {
            let entry = entry.trim();
            if entry.is_empty() {
                continue;
            }
            let (key_id, pk_b64) = match entry.split_once(':') {
                Some((id, pk)) => (id.trim().to_string(), pk.trim()),
                None => ("default".to_string(), entry),
            };
            let bytes = base64::engine::general_purpose::STANDARD
                .decode(pk_b64)
                .map_err(|e| AppError::Internal(format!("invalid pubkey base64: {e}")))?;
            let arr: [u8; 32] = bytes
                .try_into()
                .map_err(|_| AppError::Internal("pubkey must be 32 bytes".into()))?;
            let vk = VerifyingKey::from_bytes(&arr)
                .map_err(|e| AppError::Internal(format!("invalid pubkey: {e}")))?;
            keys.insert(key_id, vk);
        }

        if keys.is_empty() {
            return Err(AppError::Internal(
                "AKIRA_LICENSE_PUBKEY parsed to zero keys".into(),
            ));
        }

        Ok(Self { keys })
    }

    pub fn verify(&self, envelope: &SignedLicenseEnvelope) -> AppResult<LicensePayload> {
        if envelope.algorithm != "ed25519" {
            return Err(AppError::Internal(format!(
                "unsupported algorithm: {}",
                envelope.algorithm
            )));
        }

        let vk = self.keys.get(&envelope.key_id).ok_or_else(|| {
            AppError::Internal(format!("unknown signing key_id: {}", envelope.key_id))
        })?;

        let payload_bytes = base64::engine::general_purpose::STANDARD
            .decode(&envelope.payload)
            .map_err(|e| AppError::Internal(format!("invalid payload base64: {e}")))?;
        let sig_bytes = base64::engine::general_purpose::STANDARD
            .decode(&envelope.signature)
            .map_err(|e| AppError::Internal(format!("invalid signature base64: {e}")))?;
        let sig_arr: [u8; 64] = sig_bytes
            .try_into()
            .map_err(|_| AppError::Internal("signature must be 64 bytes".into()))?;
        let signature = Signature::from_bytes(&sig_arr);

        vk.verify(&payload_bytes, &signature)
            .map_err(|_| AppError::Internal("license signature verification failed".into()))?;

        serde_json::from_slice::<LicensePayload>(&payload_bytes)
            .map_err(|e| AppError::Internal(format!("license payload decode failed: {e}")))
    }
}

#[derive(Debug, Clone)]
pub struct SignedLicenseEnvelope {
    pub key_id: String,
    pub algorithm: String,
    pub payload: String,
    pub signature: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct LicensePayload {
    pub key_id: String,
    pub customer_id: String,
    pub product_key: String,
    pub plan_key: String,
    #[serde(default)]
    pub features: HashMap<String, bool>,
    pub fingerprint_hash: String,
    pub issued_at: String,
    pub valid_until: String,
}
