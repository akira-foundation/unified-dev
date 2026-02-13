use base64::Engine;
use rand::RngCore;

use crate::error::{AppError, AppResult};

const KEYRING_SERVICE: &str = "unified-dev";
const KEYRING_ACCOUNT: &str = "token-encryption-key";

pub struct KeyStore;

impl KeyStore {
    pub fn load_or_create_key() -> AppResult<[u8; 32]> {
        let entry = keyring::Entry::new(KEYRING_SERVICE, KEYRING_ACCOUNT)?;
        match entry.get_password() {
            Ok(encoded) => {
                let bytes = base64::engine::general_purpose::STANDARD.decode(encoded)?;
                let key: [u8; 32] = bytes
                    .try_into()
                    .map_err(|_| AppError::Crypto)?;
                Ok(key)
            }
            Err(keyring::Error::NoEntry) => {
                let mut key = [0u8; 32];
                rand::rngs::OsRng.fill_bytes(&mut key);
                let encoded = base64::engine::general_purpose::STANDARD.encode(key);
                entry.set_password(&encoded)?;
                Ok(key)
            }
            Err(error) => Err(AppError::Keyring(error)),
        }
    }
}
