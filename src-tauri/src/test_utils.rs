//! Shared test helpers for unit tests. Only compiled under `cfg(test)`.

use std::sync::Arc;

use sqlx::sqlite::SqlitePoolOptions;
use sqlx::SqlitePool;

use crate::app::support::security::TokenCipher;
use crate::providers::default_registry;
use crate::state::AppState;

/// Builds an in-memory SQLite pool with all migrations applied.
pub async fn setup_test_db() -> SqlitePool {
    let pool = SqlitePoolOptions::new()
        .max_connections(1)
        .connect("sqlite::memory:")
        .await
        .expect("failed to open in-memory sqlite");

    sqlx::query("PRAGMA foreign_keys = ON")
        .execute(&pool)
        .await
        .expect("failed to enable foreign keys");

    sqlx::migrate!("./src/database/migrations")
        .run(&pool)
        .await
        .expect("failed to run migrations");

    pool
}

/// Builds a deterministic `AppState` suitable for unit tests. The cipher uses
/// a zeroed key (no keyring); the provider factory is the default registry.
pub async fn make_test_state() -> AppState {
    let pool = setup_test_db().await;
    let cipher = TokenCipher::new([0u8; 32]);
    let factory = default_registry().expect("failed to build provider factory");
    AppState::new(Arc::new(factory), Arc::new(cipher), pool)
}

/// Inserts a provider row and returns its id. Mirrors the columns used by
/// `app::providers::credentials` so production code paths can read it back.
pub async fn seed_provider(pool: &SqlitePool, id: &str, kind: &str) -> String {
    sqlx::query(
        "INSERT INTO providers (id, name, kind, auth_type, auth_payload, created_at)
         VALUES (?, ?, ?, 'pat', '{\"token\":\"test\"}', datetime('now'))",
    )
    .bind(id)
    .bind(format!("{kind} test"))
    .bind(kind)
    .execute(pool)
    .await
    .expect("failed to insert provider");
    id.to_string()
}

/// Inserts an organization linked to the given provider.
pub async fn seed_organization(pool: &SqlitePool, id: &str, provider_id: &str) -> String {
    sqlx::query(
        "INSERT INTO organizations (id, name, provider_id, created_at)
         VALUES (?, ?, ?, datetime('now'))",
    )
    .bind(id)
    .bind(format!("org-{id}"))
    .bind(provider_id)
    .execute(pool)
    .await
    .expect("failed to insert organization");
    id.to_string()
}

/// Inserts a selected organization repo. Returns the repo name.
pub async fn seed_org_repo(
    pool: &SqlitePool,
    org_id: &str,
    owner: &str,
    repo_name: &str,
) -> String {
    sqlx::query(
        "INSERT INTO organization_repos
            (organization_id, owner, repo_name, visibility, is_selected, auto_sync, created_at)
         VALUES (?, ?, ?, 'public', 1, 1, datetime('now'))",
    )
    .bind(org_id)
    .bind(owner)
    .bind(repo_name)
    .execute(pool)
    .await
    .expect("failed to insert organization_repos");
    repo_name.to_string()
}
