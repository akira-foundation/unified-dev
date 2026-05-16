CREATE TABLE notifications (
    id TEXT NOT NULL PRIMARY KEY,
    category TEXT NOT NULL,
    severity TEXT NOT NULL DEFAULT 'info',
    title TEXT NOT NULL,
    body TEXT,
    action_type TEXT,
    action_payload TEXT,
    read_at TEXT,
    created_at TEXT NOT NULL,
    expires_at TEXT
);

CREATE INDEX idx_notifications_created_at ON notifications (created_at DESC);
CREATE INDEX idx_notifications_read_at ON notifications (read_at);
CREATE INDEX idx_notifications_category ON notifications (category);

CREATE TABLE notification_prefs (
    category TEXT NOT NULL PRIMARY KEY,
    in_app INTEGER NOT NULL DEFAULT 1,
    os_notify INTEGER NOT NULL DEFAULT 1,
    updated_at TEXT NOT NULL
);
