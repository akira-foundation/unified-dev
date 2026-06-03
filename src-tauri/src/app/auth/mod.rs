pub mod ensure;
pub mod logout;
pub mod oauth;

pub use ensure::ensure_authenticated;
pub use logout::logout;
pub use oauth::{login_with_provider, LoginResult};

pub async fn current_customer_id(pool: &sqlx::SqlitePool) -> Option<String> {
    sqlx::query_scalar::<_, Option<String>>("SELECT customer_id FROM license WHERE id = 'local'")
        .fetch_optional(pool)
        .await
        .ok()
        .flatten()
        .flatten()
}
