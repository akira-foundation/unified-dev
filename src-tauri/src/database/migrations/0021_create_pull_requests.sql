CREATE TABLE IF NOT EXISTS pull_requests (
    id TEXT PRIMARY KEY NOT NULL,
    external_id TEXT NOT NULL,
    provider TEXT NOT NULL,
    org_id TEXT NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    repo_name TEXT NOT NULL,
    number INTEGER NOT NULL,
    title TEXT NOT NULL,
    body TEXT,
    state TEXT NOT NULL DEFAULT 'open',
    url TEXT NOT NULL,
    head TEXT NOT NULL,
    base TEXT NOT NULL,
    head_sha TEXT NOT NULL,
    is_draft INTEGER NOT NULL DEFAULT 0,
    merged_at TEXT,
    author TEXT,
    labels TEXT NOT NULL DEFAULT '[]',
    reviewers TEXT NOT NULL DEFAULT '[]',
    ci_status TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    synced_at TEXT NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_pull_requests_external ON pull_requests(org_id, provider, repo_name, number);
CREATE INDEX IF NOT EXISTS idx_pull_requests_org ON pull_requests(org_id);
CREATE INDEX IF NOT EXISTS idx_pull_requests_state ON pull_requests(state);
