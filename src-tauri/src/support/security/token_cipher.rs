use aes_gcm::aead::{Aead, KeyInit};
use aes_gcm::{Aes256Gcm, Nonce};
use base64::Engine;
use rand::RngCore;

use crate::support::error::{AppError, AppResult};

const NONCE_LENGTH: usize = 12;

pub struct TokenCipher {
    key: [u8; 32],
}

impl TokenCipher {
    pub fn new(key: [u8; 32]) -> Self {
        Self { key }
    }

    pub fn encrypt(&self, plaintext: &str) -> AppResult<String> {
        let cipher = Aes256Gcm::new_from_slice(&self.key).map_err(|_| AppError::Crypto)?;
        let mut nonce_bytes = [0u8; NONCE_LENGTH];
        rand::rngs::OsRng.fill_bytes(&mut nonce_bytes);
        let nonce = Nonce::from_slice(&nonce_bytes);
        let ciphertext = cipher
            .encrypt(nonce, plaintext.as_bytes())
            .map_err(|_| AppError::Crypto)?;

        let mut combined = Vec::with_capacity(NONCE_LENGTH + ciphertext.len());
        combined.extend_from_slice(&nonce_bytes);
        combined.extend_from_slice(&ciphertext);

        Ok(base64::engine::general_purpose::STANDARD.encode(combined))
    }

    pub fn decrypt(&self, encoded: &str) -> AppResult<String> {
        let cipher = Aes256Gcm::new_from_slice(&self.key).map_err(|_| AppError::Crypto)?;
        let bytes = base64::engine::general_purpose::STANDARD.decode(encoded)?;
        if bytes.len() <= NONCE_LENGTH {
            return Err(AppError::Crypto);
        }

        let (nonce_bytes, ciphertext) = bytes.split_at(NONCE_LENGTH);
        let nonce = Nonce::from_slice(nonce_bytes);
        let plaintext = cipher
            .decrypt(nonce, ciphertext)
            .map_err(|_| AppError::Crypto)?;
        let decoded = String::from_utf8(plaintext).map_err(|_| AppError::Crypto)?;
        Ok(decoded)
    }
}
