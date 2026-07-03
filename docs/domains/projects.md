# Projects

## What this is (and isn't)

Despite the name, this is not a kanban board. There is no board/column/card model
anywhere in the schema or backend - `Project` is a lightweight grouping that links a
local checkout to an issue source and a VCS sync target, so the UI can show one unified
issue list for "this thing I'm working on" even when the issues live in a different
system than the code.

## Data model

- `projects` - `id`, `name`, `provider`, `external_id` (optional - the provider's own
 project/team ID if this maps to one), `color`, `org_id`, timestamps.
- `project_repos` - `id`, `project_id`, `name`, `default_vcs_source_id`, timestamps. A
 project can have more than one linked repo.
- `repo_sources` - `id`, `project_repo_id`, `provider`, `ref_type`, `reference` (column
 named `ref`), `is_issue_source` (bool), `is_vcs_target` (bool), `created_at`. This is
 the join that says "for this repo, pull issues from Linear team X, and open PRs against
 GitHub repo Y" - the two roles are independent flags, so a source can be one, the
 other, or both.

(An earlier `project_sources` table from migration `0041_create_projects.sql` was
replaced by `repo_sources` in `0042_project_repos.sql`.)

## Backend

`src-tauri/src/app/projects/mod.rs` holds the structs and CRUD logic;
`src-tauri/src/commands/projects.rs` exposes the Tauri commands: `project_list`,
`project_create`, `project_update`, `project_delete`, `project_repo_list`,
`project_repo_create`, `project_repo_update`, `project_repo_delete`, `repo_source_list`,
`repo_source_add`, `repo_source_remove`.

## Sync behavior

Adding a repo source (`repo_source_add`) is the sync trigger, not a separate button or
poller tick. When `is_issue_source` is true, the handler spawns a background async task
(`tauri::async_runtime::spawn`) that calls `app::tracker::sync()` for that provider, then
emits a `sync:completed` event the frontend listens for to refresh its view.

This is fire-and-forget: errors from the spawned sync are silently discarded (`let _ =`
on the join result). A failed sync leaves the project with stale/empty issue data and no
visible error - worth knowing when debugging "why is this project's issue list empty."

## Relationship to Issues and Tracker

The actual issue fetch is delegated entirely to [tracker.md](tracker.md) (for
Linear/Jira sources) or [issues-and-prs.md](issues-and-prs.md) (for VCS-native issue
sources) - `app/projects/mod.rs` itself has no HTTP client and no provider-specific
logic; it only owns the linking table.
