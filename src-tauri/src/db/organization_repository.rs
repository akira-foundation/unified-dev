use async_trait::async_trait;
use sqlx::SqlitePool;

use crate::db::models::{OrganizationRecord, OrganizationSummary};
use crate::error::AppResult;

#[async_trait]
pub trait OrganizationRepository: Send + Sync {
    async fn create(&self, organization: &OrganizationRecord) -> AppResult<OrganizationSummary>;
    async fn delete(&self, organization_id: &str) -> AppResult<()>;
    async fn list(&self) -> AppResult<Vec<OrganizationSummary>>;
    async fn list_by_provider(&self, provider_id: &str) -> AppResult<Vec<OrganizationSummary>>;
    async fn count_by_provider(&self, provider_id: &str) -> AppResult<i64>;
}

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
    async fn create(&self, organization: &OrganizationRecord) -> AppResult<OrganizationSummary> {
        sqlx::query(
            "INSERT INTO organizations (id, name, provider_id, created_at) VALUES (?, ?, ?, ?)",
        )
        .bind(&organization.id)
        .bind(&organization.name)
        .bind(&organization.provider_id)
        .bind(&organization.created_at)
        .execute(&self.pool)
        .await?;

        Ok(OrganizationSummary {
            id: organization.id.clone(),
            name: organization.name.clone(),
            provider_id: organization.provider_id.clone(),
            created_at: organization.created_at.clone(),
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
            "SELECT id, name, provider_id, created_at FROM organizations ORDER BY created_at DESC",
        )
        .fetch_all(&self.pool)
        .await?;

        Ok(organizations)
    }

    async fn list_by_provider(&self, provider_id: &str) -> AppResult<Vec<OrganizationSummary>> {
        let organizations = sqlx::query_as::<_, OrganizationSummary>(
            "SELECT id, name, provider_id, created_at FROM organizations WHERE provider_id = ? ORDER BY created_at DESC",
        )
        .bind(provider_id)
        .fetch_all(&self.pool)
        .await?;

        Ok(organizations)
    }

    async fn count_by_provider(&self, provider_id: &str) -> AppResult<i64> {
        let count = sqlx::query_scalar::<_, i64>(
            "SELECT COUNT(1) FROM organizations WHERE provider_id = ?",
        )
        .bind(provider_id)
        .fetch_one(&self.pool)
        .await?;

        Ok(count)
    }
}
