use sqlx::sqlite::{SqliteConnectOptions, SqlitePoolOptions};
use sqlx::{Row, SqlitePool};

async fn open(path: &std::path::Path, key_hex: &str) -> Result<SqlitePool, sqlx::Error> {
    let key_hex = key_hex.to_string();
    let options = SqliteConnectOptions::new()
        .filename(path)
        .create_if_missing(true);

    SqlitePoolOptions::new()
        .max_connections(1)
        .acquire_timeout(std::time::Duration::from_millis(500))
        .after_connect(move |conn, _meta| {
            let key_hex = key_hex.clone();
            Box::pin(async move {
                sqlx::query(&format!("PRAGMA key = \"x'{key_hex}'\""))
                    .execute(&mut *conn)
                    .await?;
                sqlx::query("PRAGMA journal_mode = WAL")
                    .execute(&mut *conn)
                    .await?;
                Ok(())
            })
        })
        .connect_with(options)
        .await
}

#[tokio::test]
async fn wrong_key_cannot_read_encrypted_db() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("spike.db");
    let right_key = "11".repeat(32);
    let wrong_key = "22".repeat(32);

    let pool = open(&path, &right_key).await.unwrap();
    sqlx::query("CREATE TABLE t (id INTEGER PRIMARY KEY, v TEXT)")
        .execute(&pool)
        .await
        .unwrap();
    sqlx::query("INSERT INTO t (v) VALUES ('hello')")
        .execute(&pool)
        .await
        .unwrap();
    pool.close().await;

    let reopened = open(&path, &right_key).await.unwrap();
    let row = sqlx::query("SELECT v FROM t WHERE id = 1")
        .fetch_one(&reopened)
        .await
        .unwrap();
    assert_eq!(row.get::<String, _>("v"), "hello");
    reopened.close().await;

    let wrong = open(&path, &wrong_key).await;
    match wrong {
        Err(_) => {}
        Ok(pool) => {
            let result = sqlx::query("SELECT v FROM t WHERE id = 1")
                .fetch_one(&pool)
                .await;
            assert!(result.is_err(), "wrong key must not decrypt existing data");
            pool.close().await;
        }
    }
}

#[tokio::test]
async fn wal_and_sqlcipher_coexist() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("spike-wal.db");
    let key = "33".repeat(32);

    let pool = open(&path, &key).await.unwrap();
    let mode: String = sqlx::query_scalar("PRAGMA journal_mode")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(mode.to_lowercase(), "wal");
    pool.close().await;
}

#[tokio::test]
async fn sqlcipher_export_is_available() {
    let dir = tempfile::tempdir().unwrap();
    let source_path = dir.path().join("spike-plain.db");
    let target_path = dir.path().join("spike-encrypted.db");
    let key = "44".repeat(32);

    let plain = SqlitePoolOptions::new()
        .max_connections(1)
        .connect_with(
            SqliteConnectOptions::new()
                .filename(&source_path)
                .create_if_missing(true),
        )
        .await
        .unwrap();
    sqlx::query("CREATE TABLE t (id INTEGER PRIMARY KEY, v TEXT)")
        .execute(&plain)
        .await
        .unwrap();
    sqlx::query("INSERT INTO t (v) VALUES ('migrated')")
        .execute(&plain)
        .await
        .unwrap();

    sqlx::query(&format!(
        "ATTACH DATABASE '{}' AS encrypted KEY \"x'{key}'\"",
        target_path.display()
    ))
    .execute(&plain)
    .await
    .unwrap();
    sqlx::query("SELECT sqlcipher_export('encrypted')")
        .execute(&plain)
        .await
        .unwrap();
    sqlx::query("DETACH DATABASE encrypted")
        .execute(&plain)
        .await
        .unwrap();
    plain.close().await;

    let encrypted = open(&target_path, &key).await.unwrap();
    let row = sqlx::query("SELECT v FROM t WHERE id = 1")
        .fetch_one(&encrypted)
        .await
        .unwrap();
    assert_eq!(row.get::<String, _>("v"), "migrated");
    encrypted.close().await;
}
