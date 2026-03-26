CREATE TABLE IF NOT EXISTS sync_settings (
    id                        TEXT PRIMARY KEY NOT NULL,
    scope                     TEXT NOT NULL DEFAULT 'global',
    sync_issues_enabled       INTEGER NOT NULL DEFAULT 1,
    sync_issues_interval_secs INTEGER NOT NULL DEFAULT 900,
    sync_prs_enabled          INTEGER NOT NULL DEFAULT 1,
    sync_prs_interval_secs    INTEGER NOT NULL DEFAULT 300,
    sync_repos_enabled        INTEGER NOT NULL DEFAULT 1,
    sync_repos_interval_secs  INTEGER NOT NULL DEFAULT 1800,
    sync_orgs_enabled         INTEGER NOT NULL DEFAULT 1,
    sync_orgs_interval_secs   INTEGER NOT NULL DEFAULT 7200,
    created_at                TEXT NOT NULL,
    updated_at                TEXT NOT NULL
);
