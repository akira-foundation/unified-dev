# Issue-tracker integration plan (#14)

Provider-neutral issue-tracker seam in unified-dev, backed by the `issue-providers-rs`
crates. The crate fetches + normalizes; unified-dev persists + exposes. Adding a new
provider (Jira) = add its crate + one registry line.

## Principle

`VcsProvider` (owner/repo/u64) stays for GitHub PR/repo work. Issue-trackers get a
**separate, parallel seam** (`tracker`) so Linear/Jira do not fight the GitHub-shaped trait.

## Dependencies (`src-tauri/Cargo.toml`)

```toml
issue-provider-core = "0.1"
issue-provider-linear = "0.1"
```

Published on crates.io (no path dep).

## Module layout (`src-tauri/src/tracker/`, isolated from `providers/`)

```
tracker/
  mod.rs
  registry.rs    # TrackerRegistry: kind -> TrackerFactory
  factory.rs     # TrackerFactory: build(auth) -> Arc<dyn Tracker>
  tracker.rs     # Tracker trait (the unified-dev port)
  dto.rs         # neutral DTOs
  map.rs         # core models -> DTO (shared by all drivers)
  drivers/
    linear.rs    # LinearTracker wraps issue-provider-linear client
```

## Port trait (`tracker.rs`)

Async-trait, string ids, workspace/project scope (not owner/repo). Maps 1:1 to the crate's
capability traits.

```rust
trait Tracker: Send + Sync {
    fn kind(&self) -> TrackerKind;
    async fn list_issues(&self, filter: TrackerIssueFilter, page: Option<TrackerPage>)
        -> AppResult<TrackerPageResult<TrackerIssue>>;
    async fn get_issue(&self, id: &str) -> AppResult<TrackerIssue>;
    async fn create_issue(&self, draft: TrackerIssueDraft) -> AppResult<TrackerIssue>;
    async fn update_issue(&self, id: &str, patch: TrackerIssuePatch) -> AppResult<TrackerIssue>;
    async fn close_issue(&self, id: &str) -> AppResult<TrackerIssue>;
    async fn delete_issue(&self, id: &str) -> AppResult<()>;
    async fn list_projects/milestones/teams/users/labels/cycles(...) -> ...;
}
```

`TrackerIssueDraft` / `TrackerIssuePatch` mirror the crate's `IssueDraft` / `IssuePatch`.
`TrackerIssueFilter { team: Option<String>, project: Option<String> }` — default empty = all.

## Neutral DTOs (`dto.rs`)

`TrackerIssue { id: String, title, status, category: Option<StatusCategory>, project,
milestone, assignee, priority, updated_at }`. Plus `TrackerProject/Milestone/Team/User/
Label/Cycle { id, name }`. All `serde` for Tauri.

**Decision (Q2):** re-export the crate's `issue_provider_core::StatusCategory` directly in the
DTOs. Single source of truth; the crate is the contract; no mirror to drift.

## Linear adapter (`drivers/linear.rs`)

```rust
LinearTracker { client: LinearClient }   // linear().token(t).build()
impl Tracker { delegate to client.list()/get()/create()/...; map via tracker::map }
```

Token resolved from the existing encrypted credentials store (`app/providers/credentials.rs`,
`TokenCipher`).

## Persistence

**Decision (Q3):** leave the GitHub-shaped `issues` table + flow untouched. New `external_*`
tables, separate.

Migration `0040_create_tracker_tables.sql`:

- `external_issues(id TEXT PK, provider, team_id, project_id, milestone_id, title, status,
  category, assignee_id, priority, updated_at, synced_at, raw JSON)`
- `external_projects`, `external_milestones`, `external_teams`, `external_users`,
  `external_labels`, `external_cycles` (`id TEXT PK, provider, name, parent fks, synced_at`)
- `tracker_sync_state(provider PK, cursor, last_synced_at)` for offline-restart resume.

## Scope of sync

**Decision (Q1):** `list_issues` pulls **all** workspace issues (Linear `list` is workspace-wide).
The backend accepts an optional `TrackerIssueFilter`; default empty = everything. The UI asks
the user how to scope (team/project selection) rather than hardcoding a filter.

## Tauri commands (`commands/tracker.rs`, registered in `lib.rs`)

Distinct names from the GitHub `*_issue` commands:

`tracker_sync`, `tracker_list_issues`, `tracker_get_issue`, `tracker_create_issue`,
`tracker_update_issue`, `tracker_close_issue`, `tracker_delete_issue`,
`tracker_list_projects`, `tracker_list_milestones_by_project`,
`tracker_connect` (store encrypted token), `tracker_status` (connected?).

Each: resolve token -> build tracker via registry -> call crate -> upsert `external_*` ->
return DTO.

## State (`state/app_state.rs`, `setup.rs`)

Add `tracker_registry: Arc<TrackerRegistry>` (registers Linear now). Optional background delta
sync task later, reusing `abort_handles`.

## Auth UX

**Decision (Q4):** Linear personal API key entered via an **Integrations connect form**
(Settings → Integrations, currently "coming soon"). Token encrypted with `TokenCipher` and
stored in SQLite. Never leaves the device.

## Frontend (later phase)

`src/services/trackerService.ts` (invoke wrappers), Integrations connect form, kanban /
issue-view reading tracker issues.

## Jira later

Add `issue-provider-jira`, `drivers/jira.rs` (`JiraTracker`), one `registry.register(jira())`.
Same DTOs, commands, tables. No churn elsewhere.

## Phasing (PRs into `milestone/v0.12.0`)

- **P1** — deps + `tracker` module (trait, DTOs, map, LinearTracker) + registry/state.
  Backend only, unit-tested. No DB.
- **P2** — migration `0040` + `tracker_connect`/`tracker_sync`/`list`/`get` + upsert.
- **P3** — mutation commands (create/update/close/delete).
- **P4** — frontend: Integrations connect form + kanban/issue-view read.
- **P5** — full #14: projects/milestones/etc tables + commands; delta poll/webhook; resume
  cursor; 5k/60s perf target.
