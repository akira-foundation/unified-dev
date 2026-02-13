PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS organizations (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  provider_id TEXT NOT NULL,
  auth_json TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS organization_repos (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  organization_id TEXT NOT NULL,
  owner TEXT NOT NULL,
  repo_name TEXT NOT NULL,
  visibility TEXT NOT NULL,
  is_selected INTEGER NOT NULL DEFAULT 0,
  auto_sync INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL,
  FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS repos (
  id TEXT PRIMARY KEY,
  owner TEXT NOT NULL,
  repo_name TEXT NOT NULL,
  organization_id TEXT,
  created_at TEXT NOT NULL,
  FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_organization_repos_org_id ON organization_repos(organization_id);
CREATE INDEX IF NOT EXISTS idx_repos_org_id ON repos(organization_id);
