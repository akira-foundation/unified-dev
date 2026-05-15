use sqlx::SqlitePool;
use tauri::State;

use crate::state::AppState;

pub async fn delete(
    state: State<'_, AppState>,
    org_id: String,
    repo_name: String,
    number: i64,
    issue_id: Option<String>,
) -> Result<(), String> {
    let row = if let Some(issue_id) = issue_id.clone() {
        sqlx::query_as::<_, (bool, String, String, i64)>(
            "SELECT sync_with_provider, org_id, repo_name, number FROM issues WHERE id = ? LIMIT 1",
        )
        .bind(&issue_id)
        .fetch_optional(&state.db_pool)
        .await
        .map_err(|e| e.to_string())?
    } else {
        sqlx::query_as::<_, (bool, String, String, i64)>(
            "SELECT sync_with_provider, org_id, repo_name, number FROM issues WHERE org_id = ? AND repo_name = ? AND number = ? LIMIT 1",
        )
        .bind(&org_id)
        .bind(&repo_name)
        .bind(number)
        .fetch_optional(&state.db_pool)
        .await
        .map_err(|e| e.to_string())?
    };

    let (sync_with_provider, resolved_org_id, resolved_repo_name, resolved_number) =
        row.ok_or_else(|| "Issue not found".to_string())?;

    if sync_with_provider {
        let (provider, owner) =
            super::resolve_provider::resolve_provider_and_owner(&state, &resolved_org_id, &resolved_repo_name).await?;

        let delete_result = provider
            .delete_issue(&owner, &resolved_repo_name, resolved_number as u64)
            .await;

        if let Err(error) = delete_result {
            let message = error.to_string();
            let already_deleted = message.contains("410 Gone")
                || message.contains("status\":\"410\"")
                || message.contains("This issue was deleted");

            if !already_deleted {
                return Err(message);
            }
        }
    }

    delete_local_in_db(
        &state.db_pool,
        &resolved_org_id,
        &resolved_repo_name,
        resolved_number,
        issue_id.as_deref(),
    )
    .await
}

pub async fn delete_local_in_db(
    pool: &SqlitePool,
    org_id: &str,
    repo_name: &str,
    number: i64,
    issue_id: Option<&str>,
) -> Result<(), String> {
    if let Some(id) = issue_id {
        sqlx::query("DELETE FROM issues WHERE id = ?")
            .bind(id)
            .execute(pool)
            .await
            .map_err(|e| e.to_string())?;
    } else {
        sqlx::query("DELETE FROM issues WHERE org_id = ? AND repo_name = ? AND number = ?")
            .bind(org_id)
            .bind(repo_name)
            .bind(number)
            .execute(pool)
            .await
            .map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_utils::{seed_organization, seed_provider, setup_test_db};

    async fn seed_issue(pool: &SqlitePool, id: &str, number: i64) {
        sqlx::query(
            "INSERT INTO issues
                (id, external_id, provider, org_id, repo_name, number, title,
                 status, labels, assignees, url, linked_pr_numbers,
                 created_at, updated_at, synced_at)
             VALUES (?, ?, 'github', 'o1', 'r1', ?, 'title', 'open', '[]', '[]',
                     ?, '[]', 'now', 'now', 'now')",
        )
        .bind(id)
        .bind(format!("ext-{number}"))
        .bind(number)
        .bind(format!("https://example.com/{number}"))
        .execute(pool)
        .await
        .unwrap();
    }

    async fn count(pool: &SqlitePool) -> i64 {
        sqlx::query_scalar("SELECT COUNT(*) FROM issues")
            .fetch_one(pool)
            .await
            .unwrap()
    }

    #[tokio::test]
    async fn deletes_by_id_when_provided() {
        let pool = setup_test_db().await;
        seed_provider(&pool, "p1", "github").await;
        seed_organization(&pool, "o1", "p1").await;
        seed_issue(&pool, "keep", 1).await;
        seed_issue(&pool, "drop", 2).await;

        delete_local_in_db(&pool, "o1", "r1", 2, Some("drop"))
            .await
            .unwrap();

        assert_eq!(count(&pool).await, 1);
        let remaining: String = sqlx::query_scalar("SELECT id FROM issues")
            .fetch_one(&pool)
            .await
            .unwrap();
        assert_eq!(remaining, "keep");
    }

    #[tokio::test]
    async fn deletes_by_natural_key_when_no_id() {
        let pool = setup_test_db().await;
        seed_provider(&pool, "p1", "github").await;
        seed_organization(&pool, "o1", "p1").await;
        seed_issue(&pool, "a", 1).await;
        seed_issue(&pool, "b", 2).await;

        delete_local_in_db(&pool, "o1", "r1", 1, None).await.unwrap();

        assert_eq!(count(&pool).await, 1);
        let remaining_number: i64 = sqlx::query_scalar("SELECT number FROM issues")
            .fetch_one(&pool)
            .await
            .unwrap();
        assert_eq!(remaining_number, 2);
    }

    #[tokio::test]
    async fn delete_missing_row_is_a_noop() {
        let pool = setup_test_db().await;
        seed_provider(&pool, "p1", "github").await;
        seed_organization(&pool, "o1", "p1").await;

        delete_local_in_db(&pool, "o1", "r1", 99, None)
            .await
            .expect("deleting an unknown row should succeed silently");
        assert_eq!(count(&pool).await, 0);
    }
}
