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
    #[error("cipher error: {0}")]
    Cipher(#[from] akira_billing::desktop::CipherError),
    #[error("keyring error: {0}")]
    Keyring(#[from] onyx::keyring::KeyringError),
    #[error("decode error: {0}")]
    Decode(#[from] base64::DecodeError),
    #[error("json error: {0}")]
    Json(#[from] serde_json::Error),
    #[error("http error: {0}")]
    Http(#[from] reqwest::Error),
    #[error("provider error: {0}")]
    Provider(String),
    #[error("internal error: {0}")]
    Internal(String),
    #[error("{0}")]
    FreeTierLimit(String),
    #[error("gh_not_installed")]
    GhNotInstalled,
    #[error("gh_not_authenticated")]
    GhNotAuthenticated,
}

pub type AppResult<T> = Result<T, AppError>;

impl serde::Serialize for AppError {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: serde::ser::Serializer,
    {
        serializer.serialize_str(self.to_string().as_ref())
    }
}
