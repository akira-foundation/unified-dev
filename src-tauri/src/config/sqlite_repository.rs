use async_trait::async_trait;
use sqlx::SqlitePool;

use crate::config::models::{OrganizationConfig, OrganizationRepoSummary, OrganizationSummary};
use crate::config::repository::{OrganizationRepoRepository, OrganizationRepository};
use crate::error::AppResult;

pub struct SqliteOrganizationRepository {
    pool: SqlitePool,
}

impl SqliteOrganizationRepository {
    pub fn new(pool: SqlitePool) -> Self {
        Self { pool }
    }
}

#[async_trait]
impl OrganizationRepository for SqliteOrganizationRepository {
    async fn create(&self, organization: &OrganizationConfig, created_at: &str) -> AppResult<OrganizationSummary> {
        sqlx::query(
            "INSERT INTO organizations (id, name, token, created_at) VALUES (?, ?, ?, ?)",
        )
        .bind(&organization.id)
        .bind(&organization.name)
        .bind(&organization.token)
        .bind(created_at)
        .execute(&self.pool)
        .await?;

        Ok(OrganizationSummary {
            id: organization.id.clone(),
            name: organization.name.clone(),
            created_at: created_at.to_string(),
        })
    }

    async fn delete(&self, organization_id: &str) -> AppResult<()> {
        sqlx::query("DELETE FROM organizations WHERE id = ?")
            .bind(organization_id)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    async fn list(&self) -> AppResult<Vec<OrganizationSummary>> {
        let organizations = sqlx::query_as::<_, OrganizationSummary>(
            "SELECT id, name, created_at FROM organizations ORDER BY created_at DESC",
        )
        .fetch_all(&self.pool)
        .await?;

        Ok(organizations)
    }

    async fn list_with_tokens(&self) -> AppResult<Vec<OrganizationConfig>> {
        let organizations = sqlx::query_as::<_, OrganizationConfig>(
            "SELECT id, name, token FROM organizations ORDER BY created_at DESC",
        )
        .fetch_all(&self.pool)
        .await?;

        Ok(organizations)
    }
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
    async fn attach_repo(
        &self,
        organization_id: &str,
        owner: &str,
        repo_name: &str,
        auto_sync: bool,
    ) -> AppResult<OrganizationRepoSummary> {
        let result = sqlx::query(
            "INSERT INTO organization_repos (organization_id, owner, repo_name, auto_sync) VALUES (?, ?, ?, ?)",
        )
        .bind(organization_id)
        .bind(owner)
        .bind(repo_name)
        .bind(auto_sync)
        .execute(&self.pool)
        .await?;

        Ok(OrganizationRepoSummary {
            id: result.last_insert_rowid(),
            organization_id: organization_id.to_string(),
            owner: owner.to_string(),
            repo_name: repo_name.to_string(),
            auto_sync,
        })
    }

    async fn list_by_org(&self, organization_id: &str) -> AppResult<Vec<OrganizationRepoSummary>> {
        let repos = sqlx::query_as::<_, OrganizationRepoSummary>(
            "SELECT id, organization_id, owner, repo_name, auto_sync FROM organization_repos WHERE organization_id = ? ORDER BY repo_name",
        )
        .bind(organization_id)
        .fetch_all(&self.pool)
        .await?;

        Ok(repos)
    }
}
