ALTER TABLE organization_repos ADD COLUMN default_branch TEXT NOT NULL DEFAULT 'main';
ALTER TABLE organization_repos ADD COLUMN open_prs_count INTEGER NOT NULL DEFAULT 0;
