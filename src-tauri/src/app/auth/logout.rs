use sqlx::SqlitePool;
use tauri::State;

use crate::app::support::error::{AppError, AppResult};
use crate::state::AppState;

const PROVIDER_SCOPED_TABLES: [&str; 6] = [
    "organization_repos",
    "repos",
    "organizations",
    "providers",
    "tracker_sync_state",
    "tracker_credentials",
];

pub async fn logout(state: State<'_, AppState>) -> AppResult<()> {
    {
        let mut billing = state.billing.write().await;
        billing.clear_customer_token();
    }

    clear_local_provider_data(&state.db_pool).await?;

    sqlx::query(
        "UPDATE license SET customer_id = NULL, customer_email = NULL, customer_token_cipher = NULL WHERE id = 'local'",
    )
    .execute(&state.db_pool)
    .await
    .map_err(|error| AppError::Internal(format!("logout db update failed: {error}")))?;

    Ok(())
}

pub async fn clear_local_provider_data(pool: &SqlitePool) -> AppResult<()> {
    let mut conn = pool
        .acquire()
        .await
        .map_err(|error| AppError::Internal(format!("clear provider data failed: {error}")))?;

    sqlx::query("PRAGMA foreign_keys = OFF")
        .execute(&mut *conn)
        .await
        .map_err(|error| AppError::Internal(format!("clear provider data failed: {error}")))?;

    for table in PROVIDER_SCOPED_TABLES {
        sqlx::query(&format!("DELETE FROM {table}"))
            .execute(&mut *conn)
            .await
            .map_err(|error| AppError::Internal(format!("clear provider data failed: {error}")))?;
    }

    sqlx::query("PRAGMA foreign_keys = ON")
        .execute(&mut *conn)
        .await
        .map_err(|error| AppError::Internal(format!("clear provider data failed: {error}")))?;

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_utils::{seed_organization, seed_provider, setup_test_db};

    async fn count(pool: &SqlitePool, table: &str) -> i64 {
        sqlx::query_scalar(&format!("SELECT COUNT(*) FROM {table}"))
            .fetch_one(pool)
            .await
            .unwrap()
    }

    #[tokio::test]
    async fn clears_provider_data_but_keeps_local_repositories() {
        let pool = setup_test_db().await;
        let provider_id = seed_provider(&pool, "p1", "github").await;
        seed_organization(&pool, "o1", &provider_id).await;
        sqlx::query(
            "INSERT INTO repos (id, owner, repo_name, organization_id, created_at) VALUES ('r1', 'kid', 'secret', 'o1', datetime('now'))",
        )
        .execute(&pool)
        .await
        .unwrap();
        sqlx::query(
            "INSERT INTO local_repositories (id, name, default_branch, source_path, workspace_root, created_at) VALUES ('l1', 'mine', 'main', '/tmp/x', '/tmp', datetime('now'))",
        )
        .execute(&pool)
        .await
        .unwrap();

        clear_local_provider_data(&pool).await.unwrap();

        assert_eq!(count(&pool, "providers").await, 0);
        assert_eq!(count(&pool, "organizations").await, 0);
        assert_eq!(count(&pool, "repos").await, 0);
        assert_eq!(count(&pool, "local_repositories").await, 1);
    }
}
