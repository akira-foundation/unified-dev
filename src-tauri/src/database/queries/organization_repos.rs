use sqlx::SqlitePool;

use crate::app::concerns::OrganizationRepoRepository;
use crate::app::orgs::request::SelectRepoRequest;
use crate::database::models::{OrganizationRepoSummary, OrganizationRepoWithOrg};
use crate::app::support::error::AppResult;

pub struct SqliteOrganizationRepoRepository {
    pool: SqlitePool,
}

impl SqliteOrganizationRepoRepository {
    pub fn new(pool: SqlitePool) -> Self {
        Self { pool }
    }
}

#[async_trait::async_trait]
impl OrganizationRepoRepository for SqliteOrganizationRepoRepository {
    async fn list_selected_by_org(&self, organization_id: &str) -> AppResult<Vec<OrganizationRepoSummary>> {
        let repos = sqlx::query_as::<_, OrganizationRepoSummary>(
            "SELECT id, organization_id, owner, repo_name, visibility, is_selected, auto_sync, default_branch, open_prs_count, created_at FROM organization_repos WHERE organization_id = ? AND is_selected = 1 ORDER BY repo_name",
        )
        .bind(organization_id)
        .fetch_all(&self.pool)
        .await?;

        Ok(repos)
    }

    async fn list_all_selected(&self) -> AppResult<Vec<OrganizationRepoWithOrg>> {
        let repos = sqlx::query_as::<_, OrganizationRepoWithOrg>(
            "SELECT o_r.id, o_r.organization_id, org.name as organization_name, o_r.owner, o_r.repo_name, o_r.visibility, o_r.is_selected, o_r.auto_sync, o_r.default_branch, o_r.open_prs_count, o_r.created_at FROM organization_repos o_r JOIN organizations org ON org.id = o_r.organization_id WHERE o_r.is_selected = 1 ORDER BY org.name, o_r.repo_name",
        )
        .fetch_all(&self.pool)
        .await?;

        Ok(repos)
    }

    async fn replace_selected_repos(&self, organization_id: &str, repos: &[SelectRepoRequest], created_at: &str) -> AppResult<()> {
        let mut transaction = self.pool.begin().await?;

        for repo in repos {
            let updated = sqlx::query(
                "UPDATE organization_repos SET visibility = ?, is_selected = ?, auto_sync = ?, default_branch = ? WHERE organization_id = ? AND repo_name = ?",
            )
            .bind(&repo.visibility)
            .bind(repo.is_selected)
            .bind(repo.auto_sync.unwrap_or(true))
            .bind(repo.default_branch.as_deref().unwrap_or("main"))
            .bind(organization_id)
            .bind(&repo.repo_name)
            .execute(&mut *transaction)
            .await?;

            if updated.rows_affected() == 0 {
                sqlx::query(
                    "INSERT INTO organization_repos (organization_id, owner, repo_name, visibility, is_selected, auto_sync, default_branch, open_prs_count, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                )
                .bind(organization_id)
                .bind(&repo.owner)
                .bind(&repo.repo_name)
                .bind(&repo.visibility)
                .bind(repo.is_selected)
                .bind(repo.auto_sync.unwrap_or(true))
                .bind(repo.default_branch.as_deref().unwrap_or("main"))
                .bind(repo.open_prs_count.unwrap_or(0))
                .bind(created_at)
                .execute(&mut *transaction)
                .await?;
            }
        }

        transaction.commit().await?;
        Ok(())
    }

    async fn update_repo_stats(&self, organization_id: &str, repo_name: &str, default_branch: &str, visibility: &str, open_prs_count: i64) -> AppResult<()> {
        sqlx::query(
            "UPDATE organization_repos SET default_branch = ?, visibility = ?, open_prs_count = ? WHERE organization_id = ? AND repo_name = ?",
        )
        .bind(default_branch)
        .bind(visibility)
        .bind(open_prs_count)
        .bind(organization_id)
        .bind(repo_name)
        .execute(&self.pool)
        .await?;

        Ok(())
    }
}
