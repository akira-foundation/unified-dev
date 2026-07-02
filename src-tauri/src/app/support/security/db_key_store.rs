use akira_billing::desktop::{KeyStore as SdkKeyStore, TokenKeyring};
use hkdf::Hkdf;
use sha2::Sha256;
use tauri::Manager;

use crate::app::support::error::{AppError, AppResult};

const KEYRING_SERVICE: &str = "unified-dev";
const KEYRING_ACCOUNT: &str = "db-master-key";
const HKDF_INFO: &[u8] = b"unified-dev/db-key/v1";

pub struct DbKeyStore;

impl DbKeyStore {
    pub fn load_or_create_master_key(app: &tauri::AppHandle) -> AppResult<[u8; 32]> {
        let keyring = TokenKeyring::new(KEYRING_SERVICE, KEYRING_ACCOUNT);
        let mut sdk = SdkKeyStore::new(keyring);
        if cfg!(debug_assertions) {
            let app_dir = app.path().app_data_dir()?;
            std::fs::create_dir_all(&app_dir)?;
            sdk = sdk.with_debug_file(app_dir.join("dev-db-master-key.txt"));
        }
        sdk.load_or_create()
            .map_err(|err| AppError::Internal(format!("db_key_store: {err}")))
    }
}

pub fn derive_db_key(master_key: &[u8; 32], customer_id: &str) -> [u8; 32] {
    let hk = Hkdf::<Sha256>::new(Some(customer_id.as_bytes()), master_key);
    let mut key = [0u8; 32];
    hk.expand(HKDF_INFO, &mut key)
        .expect("32 bytes is a valid HKDF-SHA256 output length");
    key
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn derive_db_key_is_deterministic_per_customer() {
        let master = [7u8; 32];
        let a1 = derive_db_key(&master, "customer-a");
        let a2 = derive_db_key(&master, "customer-a");
        assert_eq!(a1, a2);
    }

    #[test]
    fn derive_db_key_differs_across_customers() {
        let master = [7u8; 32];
        let a = derive_db_key(&master, "customer-a");
        let b = derive_db_key(&master, "customer-b");
        assert_ne!(a, b);
    }
}
