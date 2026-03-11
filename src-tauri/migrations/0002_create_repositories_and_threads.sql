CREATE TABLE IF NOT EXISTS local_repositories (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  default_branch TEXT NOT NULL,
  source_path TEXT NOT NULL,
  workspace_root TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS threads (
  id TEXT PRIMARY KEY,
  repo_id TEXT NOT NULL,
  title TEXT NOT NULL,
  workspace_path TEXT NOT NULL,
  branch TEXT NOT NULL,
  status TEXT NOT NULL,
  created_at TEXT NOT NULL,
  FOREIGN KEY (repo_id) REFERENCES local_repositories(id) ON DELETE CASCADE
);
