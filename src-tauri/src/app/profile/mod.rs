pub mod types;

use crate::app::support::error::AppResult;
use types::UserProfileDto;

pub async fn get(pool: &sqlx::SqlitePool) -> AppResult<Option<UserProfileDto>> {
    Ok(sqlx::query_as::<_, UserProfileDto>(
        "SELECT email FROM user_profile WHERE id = 'local' LIMIT 1",
    )
    .fetch_optional(pool)
    .await?)
}

pub async fn set(email: &str, pool: &sqlx::SqlitePool) -> AppResult<UserProfileDto> {
    let now = chrono::Utc::now().to_rfc3339();

    sqlx::query(
        "INSERT INTO user_profile (id, email, created_at, updated_at)
         VALUES ('local', ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET
           email = excluded.email,
           updated_at = excluded.updated_at",
    )
    .bind(email)
    .bind(&now)
    .bind(&now)
    .execute(pool)
    .await?;

    Ok(UserProfileDto { email: email.to_string() })
}
