use async_trait::async_trait;
use sqlx::SqlitePool;

use crate::db::models::{OrganizationRepoSummary, OrganizationRepoWithOrg, SelectedRepositoryInput};
use crate::error::AppResult;

#[async_trait]
pub trait OrganizationRepoRepository: Send + Sync {
    async fn list_selected_by_org(&self, organization_id: &str) -> AppResult<Vec<OrganizationRepoSummary>>;
    async fn list_all_selected(&self) -> AppResult<Vec<OrganizationRepoWithOrg>>;
    async fn replace_selected_repos(
        &self,
        organization_id: &str,
        repos: &[SelectedRepositoryInput],
        created_at: &str,
    ) -> AppResult<()>;
}

pub struct SqliteOrganizationRepoRepository {
    pool: SqlitePool,
}

impl SqliteOrganizationRepoRepository {
    pub fn new(pool: SqlitePool) -> Self {
        Self { pool }
    }
}

#[async_trait]
impl OrganizationRepoRepository for SqliteOrganizationRepoRepository {
    async fn list_selected_by_org(&self, organization_id: &str) -> AppResult<Vec<OrganizationRepoSummary>> {
        let repos = sqlx::query_as::<_, OrganizationRepoSummary>(
            "SELECT id, organization_id, owner, repo_name, visibility, is_selected, auto_sync, created_at FROM organization_repos WHERE organization_id = ? AND is_selected = 1 ORDER BY repo_name",
        )
        .bind(organization_id)
        .fetch_all(&self.pool)
        .await?;

        Ok(repos)
    }

    async fn list_all_selected(&self) -> AppResult<Vec<OrganizationRepoWithOrg>> {
        let repos = sqlx::query_as::<_, OrganizationRepoWithOrg>(
            "SELECT o_r.id, o_r.organization_id, org.name as organization_name, \
             o_r.owner, o_r.repo_name, o_r.visibility, o_r.is_selected, o_r.auto_sync, o_r.created_at \
             FROM organization_repos o_r \
             JOIN organizations org ON org.id = o_r.organization_id \
             WHERE o_r.is_selected = 1 \
             ORDER BY org.name, o_r.repo_name",
        )
        .fetch_all(&self.pool)
        .await?;

        Ok(repos)
    }

    async fn replace_selected_repos(
        &self,
        organization_id: &str,
        repos: &[SelectedRepositoryInput],
        created_at: &str,
    ) -> AppResult<()> {
        let mut transaction = self.pool.begin().await?;

        sqlx::query("DELETE FROM organization_repos WHERE organization_id = ?")
            .bind(organization_id)
            .execute(&mut *transaction)
            .await?;

        for repo in repos {
            sqlx::query(
                "INSERT INTO organization_repos (organization_id, owner, repo_name, visibility, is_selected, auto_sync, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
            )
            .bind(organization_id)
            .bind(&repo.owner)
            .bind(&repo.repo_name)
            .bind(&repo.visibility)
            .bind(repo.is_selected)
            .bind(repo.auto_sync.unwrap_or(true))
            .bind(created_at)
            .execute(&mut *transaction)
            .await?;
        }

        transaction.commit().await?;
        Ok(())
    }
}
