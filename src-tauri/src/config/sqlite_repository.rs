use async_trait::async_trait;
use sqlx::SqlitePool;

use crate::config::models::{OrganizationConfig, OrganizationRepoSummary, OrganizationSummary, SelectedRepositoryInput};
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
            "INSERT INTO organizations (id, name, provider_id, auth_json, created_at) VALUES (?, ?, ?, ?, ?)",
        )
        .bind(&organization.id)
        .bind(&organization.name)
        .bind(&organization.provider_id)
        .bind(&organization.auth_json)
        .bind(created_at)
        .execute(&self.pool)
        .await?;

        Ok(OrganizationSummary {
            id: organization.id.clone(),
            name: organization.name.clone(),
            provider_id: organization.provider_id.clone(),
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

    async fn find_by_id(&self, organization_id: &str) -> AppResult<OrganizationConfig> {
        let organization = sqlx::query_as::<_, OrganizationConfig>(
            "SELECT id, name, provider_id, auth_json FROM organizations WHERE id = ?",
        )
        .bind(organization_id)
        .fetch_one(&self.pool)
        .await?;

        Ok(organization)
    }

    async fn list(&self) -> AppResult<Vec<OrganizationSummary>> {
        let organizations = sqlx::query_as::<_, OrganizationSummary>(
            "SELECT id, name, provider_id, created_at FROM organizations ORDER BY created_at DESC",
        )
        .fetch_all(&self.pool)
        .await?;

        Ok(organizations)
    }

    async fn list_with_tokens(&self) -> AppResult<Vec<OrganizationConfig>> {
        let organizations = sqlx::query_as::<_, OrganizationConfig>(
            "SELECT id, name, provider_id, auth_json FROM organizations ORDER BY created_at DESC",
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
        visibility: &str,
        is_selected: bool,
        auto_sync: bool,
        created_at: &str,
    ) -> AppResult<OrganizationRepoSummary> {
        let result = sqlx::query(
            "INSERT INTO organization_repos (organization_id, owner, repo_name, visibility, is_selected, auto_sync, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
        )
        .bind(organization_id)
        .bind(owner)
        .bind(repo_name)
        .bind(visibility)
        .bind(is_selected)
        .bind(auto_sync)
        .bind(created_at)
        .execute(&self.pool)
        .await?;

        Ok(OrganizationRepoSummary {
            id: result.last_insert_rowid(),
            organization_id: organization_id.to_string(),
            owner: owner.to_string(),
            repo_name: repo_name.to_string(),
            visibility: visibility.to_string(),
            is_selected,
            auto_sync,
            created_at: created_at.to_string(),
        })
    }

    async fn list_by_org(&self, organization_id: &str) -> AppResult<Vec<OrganizationRepoSummary>> {
        let repos = sqlx::query_as::<_, OrganizationRepoSummary>(
            "SELECT id, organization_id, owner, repo_name, visibility, is_selected, auto_sync, created_at FROM organization_repos WHERE organization_id = ? ORDER BY repo_name",
        )
        .bind(organization_id)
        .fetch_all(&self.pool)
        .await?;

        Ok(repos)
    }

    async fn list_selected_by_org(&self, organization_id: &str) -> AppResult<Vec<OrganizationRepoSummary>> {
        let repos = sqlx::query_as::<_, OrganizationRepoSummary>(
            "SELECT id, organization_id, owner, repo_name, visibility, is_selected, auto_sync, created_at FROM organization_repos WHERE organization_id = ? AND is_selected = 1 ORDER BY repo_name",
        )
        .bind(organization_id)
        .fetch_all(&self.pool)
        .await?;

        Ok(repos)
    }

    async fn list_sync_candidates(&self, organization_id: &str) -> AppResult<Vec<OrganizationRepoSummary>> {
        let repos = sqlx::query_as::<_, OrganizationRepoSummary>(
            "SELECT id, organization_id, owner, repo_name, visibility, is_selected, auto_sync, created_at FROM organization_repos WHERE organization_id = ? AND is_selected = 1 AND auto_sync = 1 ORDER BY repo_name",
        )
        .bind(organization_id)
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
