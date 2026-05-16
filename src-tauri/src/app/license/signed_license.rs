use std::collections::HashMap;

use akira_billing::license::{decode_license, verify_license};
use akira_billing::types::{LicenseSnapshotPayload, SignedLicense};

use crate::app::support::error::{AppError, AppResult};

const AKIRA_LICENSE_PUBKEY: &str = env!("AKIRA_LICENSE_PUBKEY");

#[derive(Debug, Clone)]
pub struct Keyring {
    keys: HashMap<String, String>,
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
                Some((id, pk)) => (id.trim().to_string(), pk.trim().to_string()),
                None => ("default".to_string(), entry.to_string()),
            };
            keys.insert(key_id, pk_b64);
        }

        if keys.is_empty() {
            return Err(AppError::Internal(
                "AKIRA_LICENSE_PUBKEY parsed to zero keys".into(),
            ));
        }

        Ok(Self { keys })
    }

    pub fn verify(&self, envelope: &SignedLicenseEnvelope) -> AppResult<LicenseSnapshotPayload> {
        let signed = SignedLicense {
            key_id: envelope.key_id.clone(),
            algorithm: envelope.algorithm.clone(),
            payload: envelope.payload.clone(),
            signature: envelope.signature.clone(),
            valid_until: String::new(),
        };

        let pk = self.keys.get(&envelope.key_id).ok_or_else(|| {
            AppError::Internal(format!("unknown signing key_id: {}", envelope.key_id))
        })?;

        let valid = verify_license(&signed, pk)
            .map_err(|e| AppError::Internal(format!("license verify failed: {e}")))?;
        if !valid {
            return Err(AppError::Internal(
                "license signature verification failed".into(),
            ));
        }

        let decoded = decode_license(&signed)
            .map_err(|e| AppError::Internal(format!("license decode failed: {e}")))?;
        Ok(decoded.payload)
    }
}

#[derive(Debug, Clone)]
pub struct SignedLicenseEnvelope {
    pub key_id: String,
    pub algorithm: String,
    pub payload: String,
    pub signature: String,
}
