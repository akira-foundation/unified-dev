use std::path::Path;

use aes_gcm::aead::{Aead, KeyInit};
use aes_gcm::{Aes256Gcm, Nonce};
use rand::RngCore;
use sha2::{Digest, Sha256};
use tauri::Manager;

use crate::app::support::error::{AppError, AppResult};

const MACHINE_ID_FILE: &str = "machine_id";
const BUNDLE_ID: &str = "com.kid.unified-dev";

#[derive(Debug, Clone)]
pub struct MachineIdentity {
    pub id: String,
    pub created_at_sig: Option<String>,
}

fn derive_key() -> [u8; 32] {
    let username = std::env::var("USER")
        .or_else(|_| std::env::var("USERNAME"))
        .unwrap_or_else(|_| "unknown".to_string());

    let mut hasher = Sha256::new();
    hasher.update(BUNDLE_ID.as_bytes());
    hasher.update(b":");
    hasher.update(username.as_bytes());
    hasher.finalize().into()
}

fn encrypt(plaintext: &[u8]) -> AppResult<Vec<u8>> {
    let key = derive_key();
    let cipher = Aes256Gcm::new_from_slice(&key).map_err(|e| AppError::Internal(e.to_string()))?;

    let mut nonce_bytes = [0u8; 12];
    rand::rng().fill_bytes(&mut nonce_bytes);
    let nonce = Nonce::from_slice(&nonce_bytes);

    let ciphertext = cipher
        .encrypt(nonce, plaintext)
        .map_err(|e| AppError::Internal(e.to_string()))?;

    let mut out = Vec::with_capacity(12 + ciphertext.len());
    out.extend_from_slice(&nonce_bytes);
    out.extend_from_slice(&ciphertext);
    Ok(out)
}

fn decrypt(data: &[u8]) -> AppResult<Vec<u8>> {
    if data.len() < 13 {
        return Err(AppError::Internal("machine_id file too short".into()));
    }
    let key = derive_key();
    let cipher = Aes256Gcm::new_from_slice(&key).map_err(|e| AppError::Internal(e.to_string()))?;
    let nonce = Nonce::from_slice(&data[..12]);
    cipher
        .decrypt(nonce, &data[12..])
        .map_err(|e| AppError::Internal(format!("machine_id decrypt failed: {e}")))
}

fn serialize(identity: &MachineIdentity) -> String {
    match &identity.created_at_sig {
        Some(sig) => format!("{}\n{}", identity.id, sig),
        None => identity.id.clone(),
    }
}

fn deserialize(raw: &str) -> MachineIdentity {
    let mut parts = raw.splitn(2, '\n');
    let id = parts.next().unwrap_or("").trim().to_string();
    let created_at_sig = parts
        .next()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty());
    MachineIdentity { id, created_at_sig }
}

pub fn get_or_create(app: &tauri::AppHandle) -> AppResult<MachineIdentity> {
    let path = identity_path(app)?;

    if let Some(identity) = try_read(&path) {
        return Ok(identity);
    }

    let identity = MachineIdentity {
        id: uuid::Uuid::new_v4().to_string().to_uppercase(),
        created_at_sig: None,
    };
    persist(&path, &identity)?;
    Ok(identity)
}

pub fn save(app: &tauri::AppHandle, identity: &MachineIdentity) -> AppResult<()> {
    let path = identity_path(app)?;
    persist(&path, identity)
}

fn identity_path(app: &tauri::AppHandle) -> AppResult<std::path::PathBuf> {
    let dir = app.path().app_data_dir()?;
    std::fs::create_dir_all(&dir)?;
    Ok(dir.join(MACHINE_ID_FILE))
}

fn try_read(path: &Path) -> Option<MachineIdentity> {
    let data = std::fs::read(path).ok()?;
    let plaintext = decrypt(&data).ok()?;
    let raw = String::from_utf8(plaintext).ok()?;
    let identity = deserialize(&raw);
    if identity.id.is_empty() {
        None
    } else {
        Some(identity)
    }
}

fn persist(path: &Path, identity: &MachineIdentity) -> AppResult<()> {
    let plaintext = serialize(identity);
    let encrypted = encrypt(plaintext.as_bytes())?;
    std::fs::write(path, &encrypted)?;
    Ok(())
}
