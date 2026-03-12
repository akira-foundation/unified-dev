CREATE TABLE skills (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    enabled INTEGER NOT NULL DEFAULT 1,
    icon_path TEXT,
    installed_at TEXT NOT NULL,
    source_path TEXT NOT NULL
);
