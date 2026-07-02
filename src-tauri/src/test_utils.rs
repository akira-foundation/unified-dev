use sqlx::sqlite::SqlitePoolOptions;
use sqlx::SqlitePool;

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

pub async fn seed_license(pool: &SqlitePool) {
    sqlx::query("INSERT INTO license (id) VALUES ('local')")
        .execute(pool)
        .await
        .expect("failed to insert license");
}

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
