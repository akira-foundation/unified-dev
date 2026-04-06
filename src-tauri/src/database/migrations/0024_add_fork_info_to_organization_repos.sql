ALTER TABLE organization_repos ADD COLUMN is_fork INTEGER NOT NULL DEFAULT 0;
ALTER TABLE organization_repos ADD COLUMN fork_owner TEXT;
ALTER TABLE organization_repos ADD COLUMN fork_repo TEXT;
