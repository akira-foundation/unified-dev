use crate::state::AppState;
use crate::app::support::error::AppResult;

pub async fn update(
    repo_id: &str,
    display_name: Option<String>,
    default_branch: Option<String>,
    default_model_id: Option<String>,
    clear_default_model_id: bool,
    review_model_id: Option<String>,
    clear_review_model_id: bool,
    db: &sqlx::SqlitePool,
) -> AppResult<()> {
    if let Some(name) = display_name {
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

    Ok(())
}

pub async fn reset_display_name(repo_id: &str, db: &sqlx::SqlitePool) -> AppResult<()> {
    sqlx::query("UPDATE local_repositories SET display_name = NULL WHERE id = ?")
        .bind(repo_id)
        .execute(db)
        .await?;
    Ok(())
}
