ALTER TABLE projects ADD COLUMN org_id TEXT REFERENCES organizations(id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS project_repos (
    id TEXT PRIMARY KEY NOT NULL,
    project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    default_vcs_source_id TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_project_repos_project ON project_repos(project_id);

CREATE TABLE IF NOT EXISTS repo_sources (
    id TEXT PRIMARY KEY NOT NULL,
    project_repo_id TEXT NOT NULL REFERENCES project_repos(id) ON DELETE CASCADE,
    provider TEXT NOT NULL,
    ref_type TEXT NOT NULL,
    ref TEXT NOT NULL,
    is_issue_source INTEGER NOT NULL DEFAULT 1,
    is_vcs_target INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    UNIQUE(provider, ref_type, ref)
);

CREATE INDEX IF NOT EXISTS idx_repo_sources_repo ON repo_sources(project_repo_id);

DROP TABLE IF EXISTS project_sources;
