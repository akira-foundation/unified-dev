CREATE TABLE IF NOT EXISTS tracker_credentials (
    provider TEXT PRIMARY KEY NOT NULL,
    token_cipher TEXT NOT NULL,
    account_id TEXT,
    account_name TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS external_issues (
    id TEXT PRIMARY KEY NOT NULL,
    provider TEXT NOT NULL,
    identifier TEXT,
    title TEXT NOT NULL,
    description TEXT,
    url TEXT,
    status TEXT NOT NULL,
    category TEXT,
    project_id TEXT,
    milestone_id TEXT,
    team_id TEXT,
    assignee_id TEXT,
    author_id TEXT,
    labels TEXT NOT NULL DEFAULT '[]',
    priority INTEGER,
    created_at TEXT,
    updated_at TEXT NOT NULL,
    synced_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_external_issues_provider ON external_issues(provider);
CREATE INDEX IF NOT EXISTS idx_external_issues_team ON external_issues(team_id);
CREATE INDEX IF NOT EXISTS idx_external_issues_project ON external_issues(project_id);

CREATE TABLE IF NOT EXISTS tracker_sync_state (
    provider TEXT PRIMARY KEY NOT NULL,
    cursor TEXT,
    last_synced_at TEXT
);
