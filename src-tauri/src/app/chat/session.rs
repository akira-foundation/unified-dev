use sqlx::SqlitePool;
use tauri::AppHandle;

use crate::ai::provider::AiRequest;
use crate::ai::providers::default_registry;
use crate::ai::system_prompt::{build_action_system_prompt, build_system_prompt};
use crate::app::chat::message::{get_messages, save_message};
use crate::app::chat::stream::{emit_done, emit_error, emit_tool_call, StreamToolCallPayload};
use crate::app::mcp;
use crate::app::skills;
use crate::app::support::error::{AppError, AppResult};
use crate::app::threads;

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
    plan_mode: bool,
    thinking_budget: String,
    fast_mode: bool,
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

    let (mcp_tools, mcp_servers, mcp_disconnected_servers) = if silent {
        (vec![], vec![], vec![])
    } else {
        let servers = mcp::load_servers(&pool).await;
        let tools = mcp::load_tools(&pool).await;
        let disconnected = mcp::load_disconnected_servers(&pool).await;
        (tools, servers, disconnected)
    };

    let system_prompt = if silent {
        build_action_system_prompt(&repo_ctx.name, &thread_ctx.workspace_path, &thread_ctx.branch)
    } else {
        let skill_content = skills::load_content(&pool).await;
        build_system_prompt(
            &repo_ctx.name,
            &thread_ctx.workspace_path,
            &thread_ctx.branch,
            &model,
            plan_mode,
            &thinking_budget,
            fast_mode,
            &skill_content,
            &mcp_tools,
            &mcp_disconnected_servers,
        )
    };

    let request = AiRequest {
        thread_id: thread_id.clone(),
        system_prompt,
        content: content.clone(),
        history,
        model: model.clone(),
        workspace_path: thread_ctx.workspace_path,
        plan_mode,
        thinking_budget,
        fast_mode,
        mcp_tools,
        mcp_servers,
        mcp_disconnected_servers,
    };

    match default_registry().dispatch(request, &app).await {
        Ok(response_text) => {
            let cleaned = process_rename_workspace(&response_text, &thread_id, &pool, &app).await;
            if !silent || !cleaned.trim().is_empty() {
                save_message(&thread_id, "assistant", &cleaned, Some(&model), None, &pool).await?;
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

async fn process_rename_workspace(
    response_text: &str,
    thread_id: &str,
    pool: &SqlitePool,
    app: &AppHandle,
) -> String {
    let mut renamed_to: Option<String> = None;

    for line in response_text.lines() {
        if let Some(new_name) = line.trim().strip_prefix("RENAME_WORKSPACE:") {
            let new_name = new_name.trim();
            if !new_name.is_empty() && threads::rename_logic(thread_id, new_name, pool).await.is_ok() {
                renamed_to = Some(new_name.to_string());
            }
            break;
        }
    }

    if let Some(ref new_name) = renamed_to {
        let label = format!("Renaming workspace to '{new_name}'");
        emit_tool_call(app, StreamToolCallPayload {
            thread_id: thread_id.to_string(),
            label: label.clone(),
            status: "running".to_string(),
            output: None,
        });
        emit_tool_call(app, StreamToolCallPayload {
            thread_id: thread_id.to_string(),
            label,
            status: "done".to_string(),
            output: None,
        });
    }

    let cleaned: String = response_text
        .lines()
        .filter(|l| !l.trim().starts_with("RENAME_WORKSPACE:"))
        .collect::<Vec<_>>()
        .join("\n");

    if cleaned.trim().is_empty() {
        if let Some(ref name) = renamed_to {
            format!("Workspace renamed to '{name}'.")
        } else {
            cleaned
        }
    } else {
        cleaned
    }
}
