use crate::app::support::error::AppResult;
use crate::app::support::security::TokenCipher;

pub async fn clear_customer_token(pool: &sqlx::SqlitePool) -> AppResult<()> {
    sqlx::query("UPDATE license SET customer_token_cipher = NULL WHERE id = 'local'")
        .execute(pool)
        .await?;
    Ok(())
}

pub async fn load_customer_token(
    pool: &sqlx::SqlitePool,
    cipher: &TokenCipher,
) -> AppResult<Option<String>> {
    let cipher_blob = sqlx::query_scalar::<_, Option<String>>(
        "SELECT customer_token_cipher FROM license WHERE id = 'local' LIMIT 1",
    )
    .fetch_optional(pool)
    .await?
    .flatten();

    let Some(blob) = cipher_blob else {
        return Ok(None);
    };
    if blob.is_empty() {
        return Ok(None);
    }

    Ok(Some(cipher.decrypt(&blob)?))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_utils::{seed_license, setup_test_db};

    #[tokio::test]
    async fn load_customer_token_returns_none_without_cipher() {
        let pool = setup_test_db().await;
        seed_license(&pool).await;
        let cipher = TokenCipher::new([0u8; 32]);
        assert!(load_customer_token(&pool, &cipher).await.unwrap().is_none());
    }

    #[tokio::test]
    async fn clear_customer_token_nulls_the_cipher_column() {
        let pool = setup_test_db().await;
        seed_license(&pool).await;
        sqlx::query("UPDATE license SET customer_token_cipher = 'blob' WHERE id = 'local'")
            .execute(&pool)
            .await
            .unwrap();

        clear_customer_token(&pool).await.unwrap();

        let value: Option<String> =
            sqlx::query_scalar("SELECT customer_token_cipher FROM license WHERE id = 'local'")
                .fetch_one(&pool)
                .await
                .unwrap();
        assert!(value.is_none());
    }
}
