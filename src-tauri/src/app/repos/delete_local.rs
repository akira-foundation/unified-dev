use std::path::Path;

use sqlx::Row;

use crate::app::support::error::AppResult;
use crate::state::AppState;

pub async fn delete_local(repo_id: String, state: tauri::State<'_, AppState>) -> AppResult<()> {
    let pool = &state.pool().await?;
    let customer_id = crate::app::auth::current_customer_id(pool).await;
    let repo_record = sqlx::query(
        "SELECT workspace_root FROM local_repositories WHERE id = ? AND customer_id IS ?",
    )
    .bind(&repo_id)
    .bind(&customer_id)
    .fetch_optional(pool)
    .await?;

    if let Some(row) = repo_record {
        let workspace_root: String = row
            .try_get("workspace_root")
            .map_err(crate::app::support::error::AppError::Database)?;
        let workspace_path = Path::new(&workspace_root);
        if workspace_path.exists() {
            std::fs::remove_dir_all(workspace_path)
                .map_err(crate::app::support::error::AppError::Io)?;
        }
    }

    sqlx::query("DELETE FROM threads WHERE repo_id = ?")
        .bind(&repo_id)
        .execute(pool)
        .await?;
    sqlx::query("DELETE FROM local_repositories WHERE id = ? AND customer_id IS ?")
        .bind(&repo_id)
        .bind(&customer_id)
        .execute(pool)
        .await?;
    Ok(())
}
