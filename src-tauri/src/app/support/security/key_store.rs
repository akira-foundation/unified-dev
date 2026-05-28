use akira_billing::desktop::{KeyStore as SdkKeyStore, TokenKeyring};
use tauri::Manager;

use crate::app::support::error::{AppError, AppResult};

const KEYRING_SERVICE: &str = "unified-dev";
const KEYRING_ACCOUNT: &str = "token-encryption-key";

pub struct KeyStore;

impl KeyStore {
    pub fn load_or_create_key(app: &tauri::AppHandle) -> AppResult<[u8; 32]> {
        let keyring = TokenKeyring::new(KEYRING_SERVICE, KEYRING_ACCOUNT);
        let mut sdk = SdkKeyStore::new(keyring);
        if cfg!(debug_assertions) {
            let app_dir = app.path().app_data_dir()?;
            std::fs::create_dir_all(&app_dir)?;
            sdk = sdk.with_debug_file(app_dir.join("dev-key.txt"));
        }
        sdk.load_or_create()
            .map_err(|err| AppError::Internal(format!("key_store: {err}")))
    }
}
