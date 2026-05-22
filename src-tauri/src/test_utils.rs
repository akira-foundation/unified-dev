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

pub async fn seed_license(pool: &SqlitePool, plan: &str, with_envelope: bool) {
    let envelope: Option<&str> = if with_envelope { Some("blob") } else { None };
    sqlx::query(
        "INSERT INTO license
            (id, token, plan, cycle, email, status, valid_until, activated_at, last_verified_at,
             license_key_id, license_algorithm, license_payload, license_signature)
         VALUES ('local', '', ?, '', 'a@b.c', 'active', '2099-01-01T00:00:00+00:00',
             '2026-01-01T00:00:00+00:00', '2026-01-01T00:00:00+00:00', ?, ?, ?, ?)",
    )
    .bind(plan)
    .bind(envelope.map(|_| "k1"))
    .bind(envelope.map(|_| "ed25519"))
    .bind(envelope)
    .bind(envelope)
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
