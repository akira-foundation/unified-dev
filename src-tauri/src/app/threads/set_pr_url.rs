use crate::support::error::AppResult;

pub async fn set_pr_url(
    thread_id: &str,
    pr_url: &str,
    pr_is_draft: bool,
    pool: &sqlx::SqlitePool,
) -> AppResult<()> {
    sqlx::query("UPDATE threads SET pr_url = ?, pr_is_draft = ? WHERE id = ?")
        .bind(pr_url)
        .bind(pr_is_draft as i64)
        .bind(thread_id)
        .execute(pool)
        .await?;

    let repo_name: Option<String> = sqlx::query_scalar(
        "SELECT lr.name FROM threads t JOIN local_repositories lr ON lr.id = t.repo_id WHERE t.id = ?",
    )
    .bind(thread_id)
    .fetch_optional(pool)
    .await
    .unwrap_or(None);

    if let Some(name) = repo_name {
        let _ = sqlx::query(
            "UPDATE organization_repos SET open_prs_count = open_prs_count + 1 WHERE repo_name = ? AND is_selected = 1",
        )
        .bind(&name)
        .execute(pool)
        .await;
    }

    Ok(())
}
