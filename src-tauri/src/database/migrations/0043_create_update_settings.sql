CREATE TABLE IF NOT EXISTS update_settings (
    id TEXT PRIMARY KEY NOT NULL DEFAULT 'local',
    backup_before_update INTEGER NOT NULL DEFAULT 1,
    backup_path TEXT,
    updated_at TEXT NOT NULL
);

INSERT OR IGNORE INTO update_settings (id, backup_before_update, backup_path, updated_at)
VALUES ('local', 1, NULL, datetime('now'));
