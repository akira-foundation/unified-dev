ALTER TABLE github_contribution_profiles ADD COLUMN total_commits_period INTEGER NOT NULL DEFAULT 0;
ALTER TABLE github_contribution_profiles ADD COLUMN total_prs_period INTEGER NOT NULL DEFAULT 0;
ALTER TABLE github_contribution_profiles ADD COLUMN total_issues_period INTEGER NOT NULL DEFAULT 0;
ALTER TABLE github_contribution_profiles ADD COLUMN total_reviews_period INTEGER NOT NULL DEFAULT 0;
