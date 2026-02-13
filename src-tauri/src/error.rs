use thiserror::Error;

#[derive(Debug, Error)]
pub enum AppError {
    #[error("database error: {0}")]
    Database(#[from] sqlx::Error),
    #[error("migration error: {0}")]
    Migration(#[from] sqlx::migrate::MigrateError),
    #[error("io error: {0}")]
    Io(#[from] std::io::Error),
    #[error("path error: {0}")]
    Path(#[from] tauri::Error),
    #[error("crypto error")]
    Crypto,
    #[error("keyring error: {0}")]
    Keyring(#[from] keyring::Error),
    #[error("decode error: {0}")]
    Decode(#[from] base64::DecodeError),
    #[error("json error: {0}")]
    Json(#[from] serde_json::Error),
    #[error("http error: {0}")]
    Http(#[from] reqwest::Error),
    #[error("provider error: {0}")]
    Provider(String),
}

pub type AppResult<T> = Result<T, AppError>;
