use base64::Engine;
use rand::RngCore;

use crate::app::support::error::{AppError, AppResult};

#[cfg(debug_assertions)]
use std::fs;
#[cfg(debug_assertions)]
use std::path::PathBuf;
#[cfg(debug_assertions)]
use tauri::Manager;

const KEYRING_SERVICE: &str = "unified-dev";
const KEYRING_ACCOUNT: &str = "token-encryption-key";

pub struct KeyStore;

impl KeyStore {
    #[allow(unused_variables)]
    pub fn load_or_create_key(app: &tauri::AppHandle) -> AppResult<[u8; 32]> {
        // In debug mode, the file is the stable source — checked before the keychain
        // to prevent a new key being generated on each recompile.
        #[cfg(debug_assertions)]
        if let Ok(encoded) = read_key_file(app) {
            return decode_key(&encoded);
        }

        let entry = keyring::Entry::new(KEYRING_SERVICE, KEYRING_ACCOUNT)?;
        match entry.get_password() {
            Ok(encoded) => {
                #[cfg(debug_assertions)]
                let _ = write_key_file(app, &encoded); // keep file in sync
                decode_key(&encoded)
            }
            Err(keyring::Error::NoEntry) => {
                let key = generate_key();
                let encoded = base64::engine::general_purpose::STANDARD.encode(key);
                let _ = entry.set_password(&encoded);
                #[cfg(debug_assertions)]
                let _ = write_key_file(app, &encoded);
                Ok(key)
            }
            Err(error) => Err(AppError::Keyring(error)),
        }
    }
}

fn decode_key(encoded: &str) -> AppResult<[u8; 32]> {
    let bytes = base64::engine::general_purpose::STANDARD.decode(encoded)?;
    let key: [u8; 32] = bytes.try_into().map_err(|_| AppError::Crypto)?;
    Ok(key)
}

fn generate_key() -> [u8; 32] {
    let mut key = [0u8; 32];
    rand::rngs::OsRng.fill_bytes(&mut key);
    key
}

#[cfg(debug_assertions)]
fn key_file_path(app: &tauri::AppHandle) -> AppResult<PathBuf> {
    let app_dir = app.path().app_data_dir()?;
    fs::create_dir_all(&app_dir)?;
    Ok(app_dir.join("dev-key.txt"))
}

#[cfg(debug_assertions)]
fn read_key_file(app: &tauri::AppHandle) -> AppResult<String> {
    let path = key_file_path(app)?;
    let encoded = fs::read_to_string(path)?;
    Ok(encoded.trim().to_string())
}

#[cfg(debug_assertions)]
fn write_key_file(app: &tauri::AppHandle, encoded: &str) -> AppResult<()> {
    let path = key_file_path(app)?;
    fs::write(path, encoded)?;
    Ok(())
}
