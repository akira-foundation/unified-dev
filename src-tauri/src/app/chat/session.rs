use sqlx::SqlitePool;
use tauri::AppHandle;

use crate::ai::provider::AiRequest;
use crate::ai::providers::default_registry;
use crate::ai::system_prompt::{build_action_system_prompt, build_system_prompt};
use crate::app::chat::message::{get_messages, save_message};
use crate::app::chat::stream::{emit_done, emit_error};
use crate::support::error::{AppError, AppResult};

struct ThreadContext {
    repo_id: String,
    workspace_path: String,
    branch: String,
}

struct RepoContext {
    name: String,
}

async fn load_thread_context(thread_id: &str, pool: &SqlitePool) -> AppResult<ThreadContext> {
    let row = sqlx::query_as::<_, (String, String, String)>(
        "SELECT repo_id, workspace_path, branch FROM threads WHERE id = ?",
    )
    .bind(thread_id)
    .fetch_optional(pool)
    .await?;

    let (repo_id, workspace_path, branch) = row.ok_or_else(|| {
        AppError::Internal(format!("Thread '{}' not found", thread_id))
    })?;

    Ok(ThreadContext { repo_id, workspace_path, branch })
}

async fn load_repo_context(repo_id: &str, pool: &SqlitePool) -> AppResult<RepoContext> {
    let row = sqlx::query_as::<_, (String,)>(
        "SELECT name FROM local_repositories WHERE id = ?",
    )
    .bind(repo_id)
    .fetch_optional(pool)
    .await?;

    let (name,) = row.ok_or_else(|| {
        AppError::Internal(format!("Repository '{}' not found", repo_id))
    })?;

    Ok(RepoContext { name })
}

/// Runs a full chat session turn: saves the user message, dispatches to the AI
/// registry (agentic loop with tool-use), then saves the assistant response.
///
/// Silent sessions (draft PR, merge, etc.) run in isolation — no chat history
/// is passed so the model cannot be confused by the ongoing conversation.
///
/// Takes ownership of `pool` and `app` so they can be moved into a
/// `tokio::spawn` closure by the calling command.
pub async fn run(
    thread_id: String,
    content: String,
    model: String,
    silent: bool,
    pool: SqlitePool,
    app: AppHandle,
) -> AppResult<()> {
    if !silent {
        save_message(&thread_id, "user", &content, None, None, &pool).await?;
    }

    let thread_ctx = load_thread_context(&thread_id, &pool).await?;
    let repo_ctx = load_repo_context(&thread_ctx.repo_id, &pool).await?;

    let history = if silent {
        vec![]
    } else {
        get_messages(&thread_id, &pool).await?
    };

    let system_prompt = if silent {
        build_action_system_prompt(&repo_ctx.name, &thread_ctx.workspace_path, &thread_ctx.branch)
    } else {
        build_system_prompt(&repo_ctx.name, &thread_ctx.workspace_path, &thread_ctx.branch)
    };

    let request = AiRequest {
        thread_id: thread_id.clone(),
        system_prompt,
        content: content.clone(),
        history,
        model: model.clone(),
        workspace_path: thread_ctx.workspace_path,
    };

    match default_registry().dispatch(request, &app).await {
        Ok(response_text) => {
            if !silent || !response_text.trim().is_empty() {
                save_message(&thread_id, "assistant", &response_text, Some(&model), None, &pool).await?;
            }
            emit_done(&app, &thread_id);
        }
        Err(e) => {
            emit_error(&app, &thread_id, &e.to_string());
            return Err(e);
        }
    }

    Ok(())
}
