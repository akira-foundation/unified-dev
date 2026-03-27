CREATE TABLE IF NOT EXISTS license (
    id TEXT NOT NULL DEFAULT 'local' PRIMARY KEY,
    token TEXT NOT NULL,
    plan TEXT NOT NULL,
    cycle TEXT NOT NULL,
    email TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active',
    valid_until TEXT NOT NULL,
    activated_at TEXT NOT NULL,
    last_verified_at TEXT NOT NULL
);
