CREATE TABLE IF NOT EXISTS github_contribution_profiles (
    id TEXT PRIMARY KEY NOT NULL,
    provider_id TEXT NOT NULL,
    login TEXT NOT NULL,
    name TEXT,
    avatar_url TEXT,
    bio TEXT,
    followers INTEGER NOT NULL DEFAULT 0,
    following INTEGER NOT NULL DEFAULT 0,
    total_contributions INTEGER NOT NULL DEFAULT 0,
    current_streak INTEGER NOT NULL DEFAULT 0,
    best_streak INTEGER NOT NULL DEFAULT 0,
    most_active_language TEXT,
    most_active_repo TEXT,
    last_synced_at TEXT,
    created_at TEXT NOT NULL,
    FOREIGN KEY (provider_id) REFERENCES providers(id) ON DELETE CASCADE
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_oss_profiles_provider ON github_contribution_profiles(provider_id);

CREATE TABLE IF NOT EXISTS github_contributed_repositories (
    id TEXT PRIMARY KEY NOT NULL,
    profile_id TEXT NOT NULL,
    name_with_owner TEXT NOT NULL,
    owner_login TEXT NOT NULL,
    description TEXT,
    primary_language TEXT,
    stars INTEGER NOT NULL DEFAULT 0,
    forks INTEGER NOT NULL DEFAULT 0,
    url TEXT NOT NULL,
    is_fork INTEGER NOT NULL DEFAULT 0,
    is_archived INTEGER NOT NULL DEFAULT 0,
    last_contribution_at TEXT,
    FOREIGN KEY (profile_id) REFERENCES github_contribution_profiles(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_oss_repos_profile ON github_contributed_repositories(profile_id);
CREATE INDEX IF NOT EXISTS idx_oss_repos_owner ON github_contributed_repositories(owner_login);

CREATE TABLE IF NOT EXISTS github_pull_requests_oss (
    id TEXT PRIMARY KEY NOT NULL,
    profile_id TEXT NOT NULL,
    repo_id TEXT NOT NULL,
    name_with_owner TEXT NOT NULL,
    number INTEGER NOT NULL,
    title TEXT NOT NULL,
    state TEXT NOT NULL,
    merged INTEGER NOT NULL DEFAULT 0,
    url TEXT NOT NULL,
    additions INTEGER NOT NULL DEFAULT 0,
    deletions INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    merged_at TEXT,
    closed_at TEXT,
    FOREIGN KEY (profile_id) REFERENCES github_contribution_profiles(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_oss_prs_profile ON github_pull_requests_oss(profile_id);
CREATE INDEX IF NOT EXISTS idx_oss_prs_state ON github_pull_requests_oss(state);
CREATE INDEX IF NOT EXISTS idx_oss_prs_merged ON github_pull_requests_oss(merged);

CREATE TABLE IF NOT EXISTS github_issues_oss (
    id TEXT PRIMARY KEY NOT NULL,
    profile_id TEXT NOT NULL,
    repo_id TEXT NOT NULL,
    name_with_owner TEXT NOT NULL,
    number INTEGER NOT NULL,
    title TEXT NOT NULL,
    state TEXT NOT NULL,
    url TEXT NOT NULL,
    comments_count INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    closed_at TEXT,
    FOREIGN KEY (profile_id) REFERENCES github_contribution_profiles(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_oss_issues_profile ON github_issues_oss(profile_id);
CREATE INDEX IF NOT EXISTS idx_oss_issues_state ON github_issues_oss(state);

CREATE TABLE IF NOT EXISTS github_reviews_oss (
    id TEXT PRIMARY KEY NOT NULL,
    profile_id TEXT NOT NULL,
    repo_id TEXT NOT NULL,
    name_with_owner TEXT NOT NULL,
    pr_number INTEGER NOT NULL,
    pr_title TEXT,
    state TEXT NOT NULL,
    url TEXT NOT NULL,
    submitted_at TEXT NOT NULL,
    FOREIGN KEY (profile_id) REFERENCES github_contribution_profiles(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_oss_reviews_profile ON github_reviews_oss(profile_id);

CREATE TABLE IF NOT EXISTS github_commits_oss (
    id TEXT PRIMARY KEY NOT NULL,
    profile_id TEXT NOT NULL,
    repo_id TEXT NOT NULL,
    name_with_owner TEXT NOT NULL,
    message TEXT,
    url TEXT,
    occurred_on TEXT NOT NULL,
    count INTEGER NOT NULL DEFAULT 1,
    FOREIGN KEY (profile_id) REFERENCES github_contribution_profiles(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_oss_commits_profile ON github_commits_oss(profile_id);
CREATE INDEX IF NOT EXISTS idx_oss_commits_day ON github_commits_oss(occurred_on);

CREATE TABLE IF NOT EXISTS github_contribution_snapshots (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    profile_id TEXT NOT NULL,
    day TEXT NOT NULL,
    contributions_count INTEGER NOT NULL DEFAULT 0,
    color TEXT,
    UNIQUE(profile_id, day),
    FOREIGN KEY (profile_id) REFERENCES github_contribution_profiles(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_oss_snapshots_day ON github_contribution_snapshots(profile_id, day);
