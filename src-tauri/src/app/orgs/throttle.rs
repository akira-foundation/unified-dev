use std::collections::HashMap;
use std::sync::RwLock;

use lazy_static::lazy_static;

lazy_static! {
    static ref THROTTLE_COOLDOWN: RwLock<HashMap<u64, i64>> = RwLock::new(HashMap::new());
}

pub const DEFAULT_THROTTLE_COOLDOWN_SECS: u64 = 60;

pub fn cooldown_remaining(installation_id: u64, now: i64) -> Option<i64> {
    let until = THROTTLE_COOLDOWN.read().ok()?.get(&installation_id).copied()?;
    (until > now).then_some(until - now)
}

pub fn set_cooldown(installation_id: u64, until_unix: i64) {
    if let Ok(mut map) = THROTTLE_COOLDOWN.write() {
        map.insert(installation_id, until_unix);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cooldown_active_then_expires() {
        set_cooldown(4242, 1000);
        assert_eq!(cooldown_remaining(4242, 900), Some(100));
        assert_eq!(cooldown_remaining(4242, 1000), None);
        assert_eq!(cooldown_remaining(4242, 1100), None);
    }

    #[test]
    fn unknown_installation_has_no_cooldown() {
        assert_eq!(cooldown_remaining(9999, 0), None);
    }
}
