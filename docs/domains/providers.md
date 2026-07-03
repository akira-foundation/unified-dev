# VCS Providers (GitHub, GitLab, Bitbucket)

## Purpose

A unified interface for git-hosting providers, so the rest of the app (orgs, repos,
issues, PRs) doesn't need to know which provider it's talking to.

## The `VcsProvider` trait

Defined in `src-tauri/src/app/concerns/vcs_provider.rs`. Async methods cover
organization/repository listing, PR CRUD (list/get/create/update/merge/comment/review),
issue CRUD, and branch operations. Not every driver implements every method - optional
operations (e.g. `update_pull_request_body`) have a default that returns a "not
supported" error rather than requiring every driver to implement everything.

Drivers live in `src-tauri/src/providers/drivers/{github,gitlab,bitbucket}/`, each with a
`Factory` that implements `ProviderDriverFactory` and is registered in
`src-tauri/src/providers/registry.rs`'s `ProviderFactory`.

## Authentication modes

`ProviderAuth` (in `src-tauri/src/providers/enums.rs`):

- **`PersonalAccessToken`** - a user-supplied PAT, stored as-is (encrypted at rest via the
 per-customer DB).
- **`GitHubOAuth`** - user-level OAuth token from the GitHub login flow, plus a refresh
 token.
- **`GitHubApp`** - a GitHub App installation. Stores *both* the OAuth access token (acts
 as the user for PR authorship/reviews) and a separately-cached installation token (acts
 as the app/bot for org-wide operations like listing installations). These have
 independent expiry and refresh logic - see
 [auth-and-sessions.md](auth-and-sessions.md) for the installation-token cache and its
 cross-customer leak fix.
- **`AppPassword`** - Bitbucket's app-password auth model.

Credentials are stored in the `providers` table as an `auth_payload` JSON blob with an
`auth_type` discriminator column; the calling code deserializes based on that
discriminator (`app/providers/auth_payload.rs`).

When multiple providers could serve the same request, PAT is preferred over OAuth, which
is preferred over GitHub App - see `app/providers/credentials.rs`.

## Non-obvious rules

- Fork-aware sync: when an issue/PR's repo is a fork, sync resolves the upstream
 (`fork_owner`/`fork_repo`, fetched lazily from the provider API on first encounter and
 cached in `organization_repos`) and syncs from there instead of the fork itself.
- Feature/plan gating that used to wrap these calls (`require_feature`, per-org limits)
 was removed with the paywall in v0.12.7 - every provider operation is available to any
 logged-in customer now.
