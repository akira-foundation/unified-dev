CREATE TABLE IF NOT EXISTS visibility_preferences (
  scope_type TEXT NOT NULL,
  scope_id TEXT NOT NULL,
  issue_scope TEXT NOT NULL DEFAULT 'my_queue',
  pr_scope TEXT NOT NULL DEFAULT 'mine_or_review_requested',
  assign_issues_to_self INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (scope_type, scope_id)
);
