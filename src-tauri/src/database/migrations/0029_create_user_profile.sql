CREATE TABLE IF NOT EXISTS user_profile (
    id TEXT NOT NULL DEFAULT 'local' PRIMARY KEY,
    email TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
