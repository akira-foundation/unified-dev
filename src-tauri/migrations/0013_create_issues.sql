CREATE TABLE IF NOT EXISTS issues (
    id TEXT PRIMARY KEY NOT NULL,
    external_id TEXT NOT NULL,
    provider TEXT NOT NULL,
    org_id TEXT NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    repo_name TEXT NOT NULL,
    number INTEGER NOT NULL,
    title TEXT NOT NULL,
    body TEXT,
    status TEXT NOT NULL DEFAULT 'open',
    state_reason TEXT,
    labels TEXT NOT NULL DEFAULT '[]',
    assignees TEXT NOT NULL DEFAULT '[]',
    author TEXT,
    url TEXT NOT NULL,
    linked_pr_numbers TEXT NOT NULL DEFAULT '[]',
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    synced_at TEXT NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_issues_external ON issues(org_id, provider, repo_name, number);
CREATE INDEX IF NOT EXISTS idx_issues_org ON issues(org_id);
CREATE INDEX IF NOT EXISTS idx_issues_status ON issues(status);
