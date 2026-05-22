CREATE TABLE IF NOT EXISTS license_public_keys (
    key_id TEXT PRIMARY KEY,
    algorithm TEXT NOT NULL,
    public_key_base64 TEXT NOT NULL,
    fetched_at TEXT NOT NULL
);
