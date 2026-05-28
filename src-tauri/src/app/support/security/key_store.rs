use base64::engine::general_purpose::STANDARD as B64;
use base64::Engine as _;
use rand::RngCore;

#[cfg(debug_assertions)]
use std::fs;
#[cfg(debug_assertions)]
use std::path::PathBuf;
#[cfg(debug_assertions)]
use tauri::Manager;

use crate::app::support::error::{AppError, AppResult};

const KEYRING_SERVICE: &str = "unified-dev";
const KEYRING_ACCOUNT: &str = "token-encryption-key";

pub struct KeyStore;

impl KeyStore {
    #[allow(unused_variables)]
    pub fn load_or_create_key(app: &tauri::AppHandle) -> AppResult<[u8; 32]> {
        #[cfg(debug_assertions)]
        if let Ok(encoded) = read_key_file(app) {
            return decode_key(&encoded);
        }

        match onyx::keyring::get(KEYRING_SERVICE, KEYRING_ACCOUNT) {
            Ok(encoded) => {
                #[cfg(debug_assertions)]
                let _ = write_key_file(app, &encoded);
                decode_key(&encoded)
            }
            Err(_) => {
                let mut key = [0u8; 32];
                rand::rng().fill_bytes(&mut key);
                let encoded = B64.encode(key);
                let _ = onyx::keyring::set(KEYRING_SERVICE, KEYRING_ACCOUNT, &encoded);
                #[cfg(debug_assertions)]
                let _ = write_key_file(app, &encoded);
                Ok(key)
            }
        }
    }
}

fn decode_key(encoded: &str) -> AppResult<[u8; 32]> {
    let bytes = B64
        .decode(encoded)
        .map_err(|e| AppError::Internal(format!("key_store decode: {e}")))?;
    bytes
        .try_into()
        .map_err(|_| AppError::Internal("key_store: key length is not 32".into()))
}

#[cfg(debug_assertions)]
fn key_file_path(app: &tauri::AppHandle) -> AppResult<PathBuf> {
    let app_dir = app.path().app_data_dir()?;
    std::fs::create_dir_all(&app_dir)?;
    Ok(app_dir.join("dev-key.txt"))
}

#[cfg(debug_assertions)]
fn read_key_file(app: &tauri::AppHandle) -> AppResult<String> {
    let path = key_file_path(app)?;
    let content = fs::read_to_string(path)?;
    Ok(content.trim().to_string())
}

#[cfg(debug_assertions)]
fn write_key_file(app: &tauri::AppHandle, encoded: &str) -> AppResult<()> {
    let path = key_file_path(app)?;
    fs::write(path, encoded)?;
    Ok(())
}
