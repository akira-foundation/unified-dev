# Issues & Pull Requests

## Sync flow

`app/issues/sync.rs` and `app/orgs/pull_requests/sync.rs` share the same shape:

1. Resolve the `VcsProvider` for the repo owner (fork-aware - see
  [providers.md](providers.md)).
2. Call the provider's `list_issues()` / `list_pull_requests()`.
3. Upsert into the `issues` / `pull_requests` table under a composite ID:
  `{org_id}:{provider_kind}:{repo_name}:{number}`.
4. When the requested scope is `"all"`, locally-cached records no longer present in the
  remote result are deleted - this is the only scope that performs cleanup, since `"all"`
  is the only fetch guaranteed to be a complete snapshot.
5. `synced_at` is stamped; `sync_with_provider` flags whether a row is still
  provider-backed (vs. a local-only draft).

## Scope filters

Every list/sync call takes a `scope`:

- `"my_queue"` - assigned to the current authenticated login.
- `"all_open"` - every open item regardless of assignee.
- `"all"` - everything, including closed/merged (drives the cleanup pass above).

## What's cached vs fetched live

**Cached locally** (survives offline, refreshed on sync): title, body, state, labels,
assignees, author, `created_at`/`updated_at`.

**Always fetched live**: PR comments, PR CI checks, job logs - these change too fast and
are too large to usefully cache, and are fetched on-demand when a PR detail view opens
those tabs.

## Linked issues

PR bodies are scanned for closing-issue keywords (`Fixes #123`, `Closes #123`, etc. - see
`app/orgs/pull_requests/linked_issues.rs`) and the matched issue numbers are stored in
`issues.linked_pr_numbers` (a JSON array), populated as part of app logic rather than the
sync pass itself.

## Relationship to Autopilot and Projects

Issues are the unit of work Autopilot batches over (see
[autopilot.md](autopilot.md)), and can be pulled into a Project board as an issue source
(see [projects.md](projects.md)).
