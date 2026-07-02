pub mod session;

pub use session::{clear_customer_token, load_customer_token};

pub fn device_fingerprint() -> String {
    akira_billing::desktop::device_fingerprint(env!("CARGO_PKG_VERSION")).fingerprint
}
