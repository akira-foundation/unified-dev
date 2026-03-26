use sqlx::SqlitePool;

use crate::app::concerns::ProviderRepository;
use crate::database::models::{ProviderRecord, ProviderSummary};
use crate::app::support::error::AppResult;

pub struct SqliteProviderRepository {
    pool: SqlitePool,
}

impl SqliteProviderRepository {
    pub fn new(pool: SqlitePool) -> Self {
        Self { pool }
    }
}

#[async_trait::async_trait]
impl ProviderRepository for SqliteProviderRepository {
    async fn create(&self, provider: &ProviderRecord) -> AppResult<ProviderSummary> {
        sqlx::query(
            "INSERT INTO providers (id, name, kind, auth_type, auth_payload, created_at, account_login, account_type) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        )
        .bind(&provider.id)
        .bind(&provider.name)
        .bind(&provider.kind)
        .bind(&provider.auth_type)
        .bind(&provider.auth_payload)
        .bind(&provider.created_at)
        .bind(&provider.account_login)
        .bind(&provider.account_type)
        .execute(&self.pool)
        .await?;

        Ok(ProviderSummary {
            id: provider.id.clone(),
            name: provider.name.clone(),
            kind: provider.kind.clone(),
            created_at: provider.created_at.clone(),
            account_login: provider.account_login.clone(),
            account_type: provider.account_type.clone(),
        })
    }

    async fn delete(&self, provider_id: &str) -> AppResult<()> {
        sqlx::query("DELETE FROM providers WHERE id = ?")
            .bind(provider_id)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    async fn list(&self) -> AppResult<Vec<ProviderSummary>> {
        let providers = sqlx::query_as::<_, ProviderSummary>(
            "SELECT id, name, kind, created_at, account_login, account_type FROM providers ORDER BY created_at DESC",
        )
        .fetch_all(&self.pool)
        .await?;

        Ok(providers)
    }

    async fn find_by_id(&self, provider_id: &str) -> AppResult<ProviderRecord> {
        let provider = sqlx::query_as::<_, ProviderRecord>(
            "SELECT id, name, kind, auth_type, auth_payload, created_at, account_login, account_type FROM providers WHERE id = ?",
        )
        .bind(provider_id)
        .fetch_one(&self.pool)
        .await?;

        Ok(provider)
    }

    async fn update_auth(&self, provider_id: &str, auth_type: &str, auth_payload: &str) -> AppResult<()> {
        sqlx::query("UPDATE providers SET auth_type = ?, auth_payload = ? WHERE id = ?")
            .bind(auth_type)
            .bind(auth_payload)
            .bind(provider_id)
            .execute(&self.pool)
            .await?;
        Ok(())
    }
}
