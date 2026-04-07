use crate::state::AppState;
use crate::app::support::error::AppResult;

pub async fn update(
    repo_id: &str,
    display_name: Option<String>,
    clear_display_name: bool,
    default_branch: Option<String>,
    default_model_id: Option<String>,
    clear_default_model_id: bool,
    review_model_id: Option<String>,
    clear_review_model_id: bool,
    default_merge_action: Option<String>,
    clear_default_merge_action: bool,
    db: &sqlx::SqlitePool,
) -> AppResult<()> {
    if clear_display_name {
        sqlx::query("UPDATE local_repositories SET display_name = NULL WHERE id = ?")
            .bind(repo_id)
            .execute(db)
            .await?;
    } else if let Some(name) = display_name {
        sqlx::query("UPDATE local_repositories SET display_name = ? WHERE id = ?")
            .bind(name)
            .bind(repo_id)
            .execute(db)
            .await?;
    }

    if let Some(branch) = default_branch {
        sqlx::query("UPDATE local_repositories SET default_branch = ? WHERE id = ?")
            .bind(branch)
            .bind(repo_id)
            .execute(db)
            .await?;
    }

    if clear_default_model_id {
        sqlx::query("UPDATE local_repositories SET default_model_id = NULL WHERE id = ?")
            .bind(repo_id)
            .execute(db)
            .await?;
    } else if let Some(model_id) = default_model_id {
        sqlx::query("UPDATE local_repositories SET default_model_id = ? WHERE id = ?")
            .bind(model_id)
            .bind(repo_id)
            .execute(db)
            .await?;
    }

    if clear_review_model_id {
        sqlx::query("UPDATE local_repositories SET review_model_id = NULL WHERE id = ?")
            .bind(repo_id)
            .execute(db)
            .await?;
    } else if let Some(model_id) = review_model_id {
        sqlx::query("UPDATE local_repositories SET review_model_id = ? WHERE id = ?")
            .bind(model_id)
            .bind(repo_id)
            .execute(db)
            .await?;
    }

    if clear_default_merge_action {
        sqlx::query("UPDATE local_repositories SET default_merge_action = NULL WHERE id = ?")
            .bind(repo_id)
            .execute(db)
            .await?;
    } else if let Some(action) = default_merge_action {
        sqlx::query("UPDATE local_repositories SET default_merge_action = ? WHERE id = ?")
            .bind(action)
            .bind(repo_id)
            .execute(db)
            .await?;
    }

    Ok(())
}
