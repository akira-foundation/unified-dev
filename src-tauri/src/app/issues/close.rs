use sqlx::SqlitePool;
use tauri::State;

use crate::state::AppState;

pub async fn close(
    state: State<'_, AppState>,
    org_id: String,
    repo_name: String,
    number: i64,
    reason: Option<String>,
) -> Result<(), String> {
    let sync_with_provider = sqlx::query_scalar::<_, Option<bool>>(
        "SELECT sync_with_provider FROM issues WHERE org_id = ? AND repo_name = ? AND number = ? LIMIT 1",
    )
    .bind(&org_id)
    .bind(&repo_name)
    .bind(number)
    .fetch_optional(&state.pool().await.map_err(|e| e.to_string())?)
    .await
    .map_err(|e| e.to_string())?
    .flatten()
    .unwrap_or(true);

    if sync_with_provider {
        let (provider, owner) =
            super::resolve_provider::resolve_provider_and_owner(&state, &org_id, &repo_name)
                .await?;

        provider
            .close_issue(&owner, &repo_name, number as u64, reason.as_deref())
            .await
            .map_err(|e| e.to_string())?;
    }

    mark_closed_in_db(
        &state.pool().await.map_err(|e| e.to_string())?,
        &org_id,
        &repo_name,
        number,
        reason.as_deref(),
    )
    .await
}

pub async fn mark_closed_in_db(
    pool: &SqlitePool,
    org_id: &str,
    repo_name: &str,
    number: i64,
    reason: Option<&str>,
) -> Result<(), String> {
    let now = chrono::Utc::now().to_rfc3339();
    let state_reason = reason.unwrap_or("completed").to_string();

    sqlx::query(
        "UPDATE issues SET status = 'closed', state_reason = ?, synced_at = ? WHERE org_id = ? AND repo_name = ? AND number = ?",
    )
    .bind(&state_reason)
    .bind(&now)
    .bind(org_id)
    .bind(repo_name)
    .bind(number)
    .execute(pool)
    .await
    .map_err(|e| e.to_string())?;

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_utils::{seed_organization, seed_provider, setup_test_db};

    async fn seed_issue(pool: &SqlitePool, number: i64) {
        sqlx::query(
            "INSERT INTO issues
                (id, external_id, provider, org_id, repo_name, number, title,
                 status, labels, assignees, url, linked_pr_numbers,
                 created_at, updated_at, synced_at)
             VALUES (?, ?, 'github', 'o1', 'r1', ?, 'title', 'open', '[]', '[]',
                     ?, '[]', 'now', 'now', 'now')",
        )
        .bind(format!("id-{number}"))
        .bind(format!("ext-{number}"))
        .bind(number)
        .bind(format!("https://example.com/{number}"))
        .execute(pool)
        .await
        .unwrap();
    }

    #[tokio::test]
    async fn marks_issue_closed_with_default_reason() {
        let pool = setup_test_db().await;
        seed_provider(&pool, "p1", "github").await;
        seed_organization(&pool, "o1", "p1").await;
        seed_issue(&pool, 1).await;

        mark_closed_in_db(&pool, "o1", "r1", 1, None).await.unwrap();

        let (status, reason): (String, String) = sqlx::query_as(
            "SELECT status, state_reason FROM issues WHERE org_id = ? AND repo_name = ? AND number = ?",
        )
        .bind("o1")
        .bind("r1")
        .bind(1i64)
        .fetch_one(&pool)
        .await
        .unwrap();
        assert_eq!(status, "closed");
        assert_eq!(reason, "completed");
    }

    #[tokio::test]
    async fn close_uses_provided_reason() {
        let pool = setup_test_db().await;
        seed_provider(&pool, "p1", "github").await;
        seed_organization(&pool, "o1", "p1").await;
        seed_issue(&pool, 7).await;

        mark_closed_in_db(&pool, "o1", "r1", 7, Some("not_planned"))
            .await
            .unwrap();

        let reason: String = sqlx::query_scalar(
            "SELECT state_reason FROM issues WHERE org_id = 'o1' AND repo_name = 'r1' AND number = 7",
        )
        .fetch_one(&pool)
        .await
        .unwrap();
        assert_eq!(reason, "not_planned");
    }

    #[tokio::test]
    async fn close_is_a_noop_on_unknown_issue() {
        let pool = setup_test_db().await;
        seed_provider(&pool, "p1", "github").await;
        seed_organization(&pool, "o1", "p1").await;

        mark_closed_in_db(&pool, "o1", "r1", 99, None)
            .await
            .expect("update should succeed even without affected rows");
    }
}
