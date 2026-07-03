# Issue Trackers (Linear, Jira)

## Why a separate seam from VcsProvider

`VcsProvider` (see [providers.md](providers.md)) is shaped around git hosting: owners,
repos, branches, PRs. Linear and Jira don't fit that shape - they're workflow-centric
(status, team, cycle, project), with no concept of a "repo". Rather than bend one trait to
cover both, the codebase has a second, parallel trait: `Tracker`
(`src-tauri/src/tracker/tracker.rs`).

## The `Tracker` trait

Async methods: `current_user()`, `list_issues()`, `get_issue()`,
`create/update/delete_issue()`, `list_projects/milestones/teams/users/labels/cycles()`,
`list_comments()`, `post_comment()`.

`TrackerIssue` DTO: `id`, `identifier` (e.g. `LIN-123`), `title`, `description`, `status`,
`category` (a normalized `StatusCategory` - not every tracker's raw status maps 1:1),
`project`, `milestone`, `team`, `assignee`, `author`, `labels`, `priority`, timestamps.

## Registry

`src-tauri/src/tracker/registry.rs`'s `TrackerRegistry` is a stateless factory:
`build(kind: &str, token: impl Into<String>) -> Arc<dyn Tracker>`. Supports `"linear"` and
`"jira"`. Jira's token is itself a small JSON blob (`{cloud_id, access_token}`) since Jira
Cloud OAuth requires a resource ID alongside the token.

Unlike VCS providers, tracker calls are **not cached locally** - every call hits the
remote API live. There is no `tracker_issues` table; a project's linked tracker issues are
fetched on demand when that project view is opened.

## Underlying implementation

The actual Linear/Jira API clients live in the `omnitrack` crate (an external dependency);
this app's `tracker/` module is a thin DTO/registry layer on top of it, so switching or
adding a tracker provider means adding a case to the registry, not rewriting call sites.
