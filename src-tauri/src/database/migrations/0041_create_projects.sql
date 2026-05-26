CREATE TABLE IF NOT EXISTS projects (
    id TEXT PRIMARY KEY NOT NULL,
    name TEXT NOT NULL,
    provider TEXT NOT NULL DEFAULT 'local',
    external_id TEXT,
    color TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_projects_provider_external
    ON projects(provider, external_id) WHERE external_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS project_sources (
    id TEXT PRIMARY KEY NOT NULL,
    project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    provider TEXT NOT NULL,
    ref_type TEXT NOT NULL,
    ref TEXT NOT NULL,
    created_at TEXT NOT NULL,
    UNIQUE(provider, ref_type, ref)
);

CREATE INDEX IF NOT EXISTS idx_project_sources_project ON project_sources(project_id);

ALTER TABLE external_issues ADD COLUMN project_name TEXT;
ALTER TABLE external_issues ADD COLUMN team_name TEXT;
ALTER TABLE external_issues ADD COLUMN milestone_name TEXT;
ALTER TABLE external_issues ADD COLUMN assignee_name TEXT;
ALTER TABLE external_issues ADD COLUMN author_name TEXT;
ALTER TABLE external_issues ADD COLUMN label_names TEXT NOT NULL DEFAULT '[]';
