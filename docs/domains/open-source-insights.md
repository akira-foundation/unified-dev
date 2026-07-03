# Open Source Insights

## Purpose

Syncs the logged-in customer's public GitHub contribution activity into local SQLite via
GraphQL, then serves it to a dashboard (`src/pages/open-source.tsx`): contribution
calendar/heatmap, streaks, contributed repos, PRs, issues, reviews, activity breakdown.

## Data pulled

`app/open_source/sync.rs` pulls, per GitHub GraphQL query (`graphql.rs`): viewer
profile, the full daily contribution calendar (count + color per day), commit/PR/issue/
review contribution totals, contributed repositories (paginated 100/page), pull requests
(OPEN/MERGED/CLOSED, paginated), issues (paginated), and PR reviews (up to 50 repos ×
50 contributions each). It also backfills every prior contribution year
(`backfill_years`), not just the current one.

GraphQL queries are inline raw strings (`VIEWER_QUERY`, `CONTRIBUTIONS_QUERY`,
`REPOS_CONTRIBUTED_QUERY`, `PULL_REQUESTS_QUERY`, `ISSUES_QUERY`, `REVIEWS_QUERY`,
`YEAR_OVERVIEW_QUERY`, `FIRST_CONTRIBUTION_YEAR_QUERY`) executed through
`GitHubDriver::graphql`/`graphql_paginated` - there is no separate `.graphql` file.

## Tables

All defined in `0032_create_open_source_contributions.sql` (plus later additive
migrations):

- `github_contribution_profiles` - one row per synced GitHub identity: totals, streaks,
 most-active language/repo, `last_synced_at`, `customer_id` (added `0046`).
- `github_contribution_snapshots` - one row per day (`UNIQUE(profile_id, day)`) - 
 the heatmap data source.
- `github_contributed_repositories`, `github_pull_requests_oss`, `github_issues_oss`,
 `github_reviews_oss` - one row per item, each keyed to `profile_id`.
- `github_commits_oss` also exists in the same migration but nothing in `sync.rs`
 inserts into it - dead table as of this writing.

## Sync trigger

Manual only. The frontend calls `invoke("sync_github_open_source_contributions")` from
`openSourceService.ts`, wired to the `OpenSourceSyncButton` component. There is no
scheduler, cron, or startup hook that triggers this sync automatically - the dashboard
shows whatever was last manually synced until the user clicks sync again.

## Sync strategy: destructive rebuild, not incremental diff

Each sync deletes all existing snapshot/repo/PR/issue/review rows for the profile, then
reinserts fresh from the GraphQL response (`sync.rs`, multiple `DELETE FROM ... WHERE
profile_id = ?` calls before the insert passes). There is no incremental/delta sync - 
every sync is a full re-pull, which is simpler but means sync time scales with total
lifetime contribution volume, not with "what changed since last sync."

## Auth edge case

If the resolved provider is a GitHub App installation with no per-user OAuth token
attached, the sync fails with `"github_app_no_user_token"` rather than falling back to
the app-level installation token - surfaced to the user via
`GithubAppNoUserTokenState.tsx` rather than silently using bot-level credentials to read
personal contribution data.

## Tauri commands

`commands/open_source.rs`: `fetch_github_contribution_summary`,
`fetch_github_contributed_repositories`, `fetch_github_pull_requests`,
`fetch_github_issues`, `fetch_github_reviews`, `fetch_github_contribution_calendar`,
`fetch_github_year_overview`, `sync_github_open_source_contributions`.

## Frontend

`src/components/open-source/`: `ContributionCalendar.tsx` (heatmap),
`ContributionStatsCards.tsx`/`StatCard.tsx` (streak/total stat cards - see the
truncation-bug note in `docs/CHANGELOG.md`), `ActivityRadarChart.tsx`,
`ContributedRepositoriesTable.tsx`, `PullRequestsTable.tsx`, `IssuesTable.tsx`,
`ReviewsTable.tsx`, `YearSelector.tsx`, filter components
(`OssOrgFilter.tsx`/`OpenSourceFilters.tsx`/`OssTableSearch.tsx`), and state components
for the empty/error paths: `GithubNotConnectedState.tsx`, `GithubRateLimitedState.tsx`,
`GithubAppNoUserTokenState.tsx`, `EmptyOpenSourceState.tsx`.
