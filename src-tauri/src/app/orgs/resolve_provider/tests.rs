use std::time::Instant;

use super::{
    clear_installation_caches, invalidate_installation_token, parse_expiry_unix, token_is_fresh,
    CachedInstallations, CachedToken, GitHubInstallation, Account,
    INSTALLATIONS_CACHE, INSTALLATION_TOKEN_CACHE, TOKEN_EXPIRY_BUFFER_SECS,
};

#[test]
fn parse_expiry_unix_reads_rfc3339() {
    assert_eq!(parse_expiry_unix("1970-01-01T00:00:10Z"), 10);
}

#[test]
fn parse_expiry_unix_falls_back_to_zero_on_garbage() {
    assert_eq!(parse_expiry_unix("not-a-date"), 0);
}

#[test]
fn token_is_fresh_respects_expiry_buffer() {
    let expires = 1_000;
    assert!(token_is_fresh(expires, expires - TOKEN_EXPIRY_BUFFER_SECS - 1));
    assert!(!token_is_fresh(expires, expires - TOKEN_EXPIRY_BUFFER_SECS));
    assert!(!token_is_fresh(expires, expires));
}

#[test]
fn invalidate_installation_token_removes_entry() {
    let id = 987_654;
    INSTALLATION_TOKEN_CACHE.write().unwrap().insert(
        id,
        CachedToken { token: "t".to_string(), expires_at_unix: i64::MAX },
    );
    assert!(INSTALLATION_TOKEN_CACHE.read().unwrap().contains_key(&id));

    invalidate_installation_token(id);
    assert!(!INSTALLATION_TOKEN_CACHE.read().unwrap().contains_key(&id));
}

#[tokio::test]
async fn clear_installation_caches_wipes_both_caches() {
    let id = 111_222;
    INSTALLATION_TOKEN_CACHE.write().unwrap().insert(
        id,
        CachedToken { token: "leaked-token".to_string(), expires_at_unix: i64::MAX },
    );
    *INSTALLATIONS_CACHE.write().await = Some(CachedInstallations {
        token: "customer-a-oauth-token".to_string(),
        installations: vec![GitHubInstallation {
            id,
            account: Account { login: "shared-org".to_string() },
        }],
        cached_at: Instant::now(),
    });

    clear_installation_caches().await;

    assert!(!INSTALLATION_TOKEN_CACHE.read().unwrap().contains_key(&id));
    assert!(INSTALLATIONS_CACHE.read().await.is_none());
}
