pub mod activate;
pub mod bootstrap;
pub mod checkout;
pub mod claim;
pub mod downgrade;
pub mod gate;
pub mod gating;
pub mod invoices;
pub mod lifecycle;
pub mod persist;
pub mod plans;
pub mod portal;
pub mod signed_license;
pub mod types;
pub mod verify;

pub use activate::activate;
pub use checkout::checkout_url;
pub use claim::{request_otp, verify_otp};
pub use downgrade::{apply_downgrade, downgrade, resume, DowngradeDto};
pub use gating::can_add;
pub use invoices::list_invoices;
pub use portal::portal;
pub use verify::{clear, get_plan, get_with_lifecycle, load_customer_token, verify};

pub fn device_fingerprint() -> String {
    akira_billing::desktop::device_fingerprint(env!("CARGO_PKG_VERSION")).fingerprint
}
