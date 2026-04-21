use tauri::State;

use crate::providers::dto::PullRequestDto;
use crate::providers::enums::PullRequestState;
use crate::state::AppState;

pub async fn sync(
    state: State<'_, AppState>,
    organization_id: String,
    repo_name: String,
    owner: Option<String>,
    scope: Option<String>,
    current_login: Option<String>,
) -> Result<Vec<PullRequestDto>, String> {
    let _ = owner;
    let (effective_owner, effective_repo, provider, is_upstream) = super::resolve_provider::resolve_pr_provider(&state, &organization_id, &repo_name).await?;
    let provider_kind = provider.kind().to_string();

    let prs = provider
        .list_pull_requests(&effective_owner, &effective_repo)
        .await
        .map_err(|e| e.to_string())?;

    let now = chrono::Utc::now().to_rfc3339();

    for pr in &prs {
        let id = format!("{organization_id}:{provider_kind}:{repo_name}:{}", pr.number);
        let labels_json = serde_json::to_string(&pr.labels).unwrap_or_else(|_| "[]".to_string());
        let reviewers_json = serde_json::to_string(&pr.reviewers).unwrap_or_else(|_| "[]".to_string());
        let state_str = match pr.state {
            crate::providers::enums::PullRequestState::Open => "open",
            crate::providers::enums::PullRequestState::Closed => "closed",
        };

        sqlx::query(
            r#"
            INSERT INTO pull_requests
                (id, external_id, provider, org_id, repo_name, number, title, body,
                 state, url, head, base, head_sha, is_draft, merged_at, author,
                 labels, reviewers, ci_status, created_at, updated_at, synced_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title      = excluded.title,
                body       = excluded.body,
                state      = excluded.state,
                head_sha   = excluded.head_sha,
                is_draft   = excluded.is_draft,
                merged_at  = excluded.merged_at,
                author     = excluded.author,
                labels     = excluded.labels,
                reviewers  = excluded.reviewers,
                ci_status  = excluded.ci_status,
                updated_at = excluded.updated_at,
                synced_at  = excluded.synced_at
            "#,
        )
        .bind(&id)
        .bind(&pr.id)
        .bind(&provider_kind)
        .bind(&organization_id)
        .bind(&repo_name)
        .bind(pr.number as i64)
        .bind(&pr.title)
        .bind(&pr.body)
        .bind(state_str)
        .bind(&pr.url)
        .bind(&pr.head)
        .bind(&pr.base)
        .bind(&pr.head_sha)
        .bind(pr.is_draft)
        .bind(&pr.merged_at)
        .bind(&pr.author)
        .bind(&labels_json)
        .bind(&reviewers_json)
        .bind(&pr.ci_status)
        .bind(&pr.created_at)
        .bind(&pr.updated_at)
        .bind(&now)
        .execute(&state.db_pool)
        .await
        .map_err(|e| e.to_string())?;
    }

    if !prs.is_empty() && !is_upstream {
        let remote_ids: std::collections::HashSet<i64> = prs.iter().map(|pr| pr.number as i64).collect();
        let local_numbers: Vec<i64> = sqlx::query_scalar::<_, i64>(
            "SELECT number FROM pull_requests WHERE org_id = ? AND repo_name = ? AND state = 'open'",
        )
        .bind(&organization_id)
        .bind(&repo_name)
        .fetch_all(&state.db_pool)
        .await
        .map_err(|e| e.to_string())?;

        for number in local_numbers {
            if !remote_ids.contains(&number) {
                sqlx::query(
                    "UPDATE pull_requests SET state = 'closed', synced_at = ? WHERE org_id = ? AND repo_name = ? AND number = ?",
                )
                .bind(&now)
                .bind(&organization_id)
                .bind(&repo_name)
                .bind(number)
                .execute(&state.db_pool)
                .await
                .map_err(|e| e.to_string())?;
            }
        }
    }

    let scope = scope.unwrap_or_else(|| "mine_or_review_requested".to_string());
    let login = current_login.map(|v| v.to_lowercase());

    let dtos: Vec<PullRequestDto> = prs
        .into_iter()
        .filter(|pr| pr.state == PullRequestState::Open)
        .map(|pr| PullRequestDto {
            id: pr.id,
            number: pr.number,
            title: pr.title,
            state: "open".to_string(),
            url: pr.url,
            head: pr.head,
            base: pr.base,
            head_sha: pr.head_sha,
            created_at: pr.created_at,
            updated_at: pr.updated_at,
            is_draft: pr.is_draft,
            merged_at: pr.merged_at,
            body: pr.body,
            author: pr.author.clone(),
            labels: pr.labels.clone(),
            reviewers: pr.reviewers.clone(),
            ci_status: pr.ci_status,
        })
        .filter(|pr| match scope.as_str() {
            "all_open" => true,
            _ => login.as_ref().map(|current| {
                pr.author.as_ref().map(|a| a.to_lowercase() == *current).unwrap_or(false)
                    || pr.reviewers.iter().any(|r| r.to_lowercase() == *current)
            }).unwrap_or(true),
        })
        .collect();

    Ok(dtos)
}
