# Organizations & Repositories

## Organizations

An `Organization` links a VCS provider account to a remote org/workspace
(`app/orgs/create.rs`). `OrganizationSummary` tracks `id`, `name`, `provider_id`,
`external_id` (the provider's own org identifier), and a computed
`selected_repos_count`.

## Repositories: remote vs local

- **Remote repositories** are synced from the provider API into `organization_repos`:
 `owner`, `repo_name`, `is_selected` (whether the user opted into syncing it),
 `is_fork`/`fork_owner`/`fork_repo`, `auto_sync`.
- **Local repositories** are the developer's own git checkouts on disk, stored in
 `local_repositories` (`id`, `name`, `source_path`, `remote_url`, `workspace_root`,
 `default_branch`). `app/repos/link_organization.rs` links a local checkout to an
 organization so issues/PRs for that repo resolve correctly.

## Sync stats

`sync_repository_stats()` (per org) and `sync_single_repo_stats()` (per repo) poll the
provider for metadata - star count, open PR count, `last_synced_at` - and update
`organization_repos`. Auto-sync is opt-in per repo (`auto_sync` column) and is what the
background poller (`app/settings/poller.rs`) checks every tick.

## Branch operations

`list_repo_branches()`, `create_repo_branch()`, `delete_repo_branch()` delegate to the
resolved `VcsProvider`. For forked repos, operations run against the *effective*
owner/repo (the upstream), resolved the same way issue/PR sync resolves it - see
[providers.md](providers.md).

## Deletion

`app/orgs/repos/save_selected.rs` and related handlers manage the selected-repos set for
an org in a single transaction, so toggling a repo's sync status is atomic.
