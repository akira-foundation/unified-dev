use akira_billing::desktop::TokenKeyring;

use crate::app::support::error::{AppError, AppResult};

const KEYRING_SERVICE: &str = "unified-dev";
const KEYRING_ACCOUNT: &str = "active-customer";

fn keyring() -> TokenKeyring {
    TokenKeyring::new(KEYRING_SERVICE, KEYRING_ACCOUNT)
}

pub fn active_customer_get() -> AppResult<Option<String>> {
    keyring()
        .get()
        .map_err(|err| AppError::Internal(format!("active_customer: {err}")))
}

pub fn active_customer_set(customer_id: &str) -> AppResult<()> {
    keyring()
        .set(customer_id)
        .map_err(|err| AppError::Internal(format!("active_customer: {err}")))
}

pub fn active_customer_clear() -> AppResult<()> {
    keyring()
        .delete()
        .map_err(|err| AppError::Internal(format!("active_customer: {err}")))
}
