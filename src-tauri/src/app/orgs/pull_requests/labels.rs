use serde::Serialize;
use tauri::State;

use crate::providers::dto::VcsRepoLabel;
use crate::state::AppState;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RepoLabelDto {
    pub name: String,
    pub color: String,
    pub description: Option<String>,
}

impl From<VcsRepoLabel> for RepoLabelDto {
    fn from(value: VcsRepoLabel) -> Self {
        Self {
            name: value.name,
            color: value.color,
            description: value.description,
        }
    }
}

pub async fn list_labels(
    state: State<'_, AppState>,
    organization_id: String,
    repo_name: String,
) -> Result<Vec<RepoLabelDto>, String> {
    let (owner, effective_repo, provider, _) =
        super::resolve_provider::resolve_pr_provider(&state, &organization_id, &repo_name).await?;

    let labels = provider
        .list_repository_labels(&owner, &effective_repo)
        .await
        .map_err(|e| e.to_string())?;

    Ok(labels.into_iter().map(RepoLabelDto::from).collect())
}

pub async fn create_label(
    state: State<'_, AppState>,
    organization_id: String,
    repo_name: String,
    name: String,
    color: Option<String>,
    description: Option<String>,
) -> Result<RepoLabelDto, String> {
    let (owner, effective_repo, provider, _) =
        super::resolve_provider::resolve_pr_provider(&state, &organization_id, &repo_name).await?;

    let created = provider
        .create_repository_label(
            &owner,
            &effective_repo,
            &name,
            color.as_deref(),
            description.as_deref(),
        )
        .await
        .map_err(|e| e.to_string())?;

    Ok(RepoLabelDto::from(created))
}

pub async fn set_labels(
    state: State<'_, AppState>,
    organization_id: String,
    repo_name: String,
    pr_number: u64,
    labels: Vec<String>,
) -> Result<Vec<String>, String> {
    let (owner, effective_repo, provider, _) =
        super::resolve_provider::resolve_pr_provider(&state, &organization_id, &repo_name).await?;

    let updated = provider
        .set_pull_request_labels(&owner, &effective_repo, pr_number, labels)
        .await
        .map_err(|e| e.to_string())?;

    let joined = updated.join(",");
    let now = chrono::Utc::now().to_rfc3339();
    sqlx::query(
        "UPDATE pull_requests
            SET labels = ?,
                updated_at = ?,
                synced_at = ?
         WHERE org_id = ? AND repo_name = ? AND number = ?",
    )
    .bind(&joined)
    .bind(&now)
    .bind(&now)
    .bind(&organization_id)
    .bind(&repo_name)
    .bind(pr_number as i64)
    .execute(&state.pool().await.map_err(|e| e.to_string())?)
    .await
    .map_err(|e| e.to_string())?;

    Ok(updated)
}
