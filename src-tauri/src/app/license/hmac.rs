use hmac::{Hmac, Mac};
use sha2::Sha256;

type HmacSha256 = Hmac<Sha256>;

pub fn sign(token: &str, plan: &str, cycle: &str, valid_until: &str, email: &str) -> String {
    let payload = format!("{plan}:{cycle}:{valid_until}:{email}");
    let mut mac = HmacSha256::new_from_slice(token.as_bytes()).expect("HMAC key is valid");
    mac.update(payload.as_bytes());
    hex::encode(mac.finalize().into_bytes())
}

pub fn verify(
    token: &str,
    plan: &str,
    cycle: &str,
    valid_until: &str,
    email: &str,
    signature: &str,
) -> bool {
    let expected = sign(token, plan, cycle, valid_until, email);
    expected == signature
}
