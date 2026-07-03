# Operations

## Release pipeline

`.github/workflows/build-and-release.yml`, triggered by pushing a `v*` tag. Two
parallel jobs, one per target (`aarch64-apple-darwin`, `x86_64-apple-darwin`), each run
the same sequence:

| Step | What happens |
|---|---|
| 1 | Set the version from the tag |
| 2 | Write a build-time `.env` from GitHub Secrets (see **Build secrets** below) |
| 3 | Import the Apple signing certificate into a throwaway CI keychain |
| 4 | Run `tauri build` - codesigning, notarization, and updater-artifact signing (see **Signing secrets** below) |
| 5 | Normalize output to `unified_dev_<version>_<arch>.app.tar.gz` and `.dmg`, with a `.sig` file (minisign signature) alongside |
| 6 | `git-cliff` generates the release body from Conventional Commits since the last tag |
| 7 | `softprops/action-gh-release` publishes the `.dmg`, `.app.tar.gz`, and `.sig` to the GitHub Release |

**Build secrets** (written into the build-time `.env`)

| Variable | Status |
|---|---|
| `AKIRA_BILLING_URL`, `AKIRA_BILLING_SECRET` | Live - same variables used for local dev, see [04-configuration.md](04-configuration.md) |
| `AKIRA_API_URL` | Dead - no consumer anywhere in the codebase |
| `GITHUB_CLIENT_ID` | Dead - no consumer anywhere in the codebase |
| `AKIRA_LICENSE_PUBKEY` | Dead - described a paywall/license flow removed in v0.12.7; not even in `.env.example` anymore |

**Signing secrets** (used by `tauri build` for codesigning/notarization)

| Variable | Purpose |
|---|---|
| `TAURI_SIGNING_PRIVATE_KEY` | Signs the updater artifact (`.sig`) |
| `APPLE_SIGNING_IDENTITY` | Codesigning identity imported into the CI keychain |
| `APPLE_ID`, `APPLE_PASSWORD` | Apple notarization auth |
| `APPLE_TEAM_ID` | Apple Developer team ID |

**Known inconsistency, not yet fixed**: this workflow still installs dependencies via
`pnpm/action-setup` + `pnpm install --frozen-lockfile`, contradicting the Bun-only
policy in [06-development.md](06-development.md) - the CI workflow was not updated when
the project standardized on Bun. It also still writes three dead variables
(`AKIRA_API_URL`, `GITHUB_CLIENT_ID`, `AKIRA_LICENSE_PUBKEY`) into the build `.env` for
no reason - none of them have a consumer in the code after the v0.12.7 paywall removal.

## Auto-update

Handled by the Tauri updater plugin, configured in `src-tauri/tauri.conf.json`:

```json
"endpoints": ["https://github.com/akira-foundation/unified-dev/releases/latest/download/latest.json"]
```

This points at GitHub's stable "latest release" download alias, which `tauri build`
generates as `latest.json` alongside the platform artifacts on every tagged release. The
client (`useUpdater.ts` hook) checks this endpoint, and if a newer version's signature
verifies against the `pubkey` in `tauri.conf.json`, offers to download and install it.

This replaced an earlier DigitalOcean Spaces CDN-hosted `latest.json` (removed in
v0.12.7 as part of the open-source transition) - deliberately with **no transitional
dual-publish period**: from the cutover point forward, only GitHub Releases serves
updates. Pre-cutover installs on the old CDN-based updater config had to fetch one more
update (the transition build) to pick up the new endpoint.

## Versioning

`scripts/sync-version.js`, run in CI after the tag-derived version is written into
`package.json`, keeps `src-tauri/tauri.conf.json`'s version field in sync so the Rust
binary and the frontend bundle report the same version string.

Release notes are auto-generated from commit history by `git-cliff` (`cliff.toml`) - this
is why Conventional Commit messages matter beyond code review: they become user-facing
changelog entries.

## Monitoring / observability

There is no external error-tracking or telemetry service wired into the app as of this
writing (no Sentry/PostHog/etc. dependency found in `package.json` or `Cargo.toml`).
Debugging a user-reported issue means reproducing locally or asking for logs from
`tauri dev`/the packaged app's log output.

## Decommissioned infrastructure

`worker/` - a Cloudflare Worker that used to front Stripe billing/OTP routes and a
DO-Spaces-backed `/download` redirect - was removed from the repository entirely in the
v0.12.7 open-source transition (confirmed dead: nothing in the app calls the worker's
own deployed URL; all billing/OAuth calls go through `AKIRA_BILLING_URL` via the
`akira_billing` SDK instead). The live Cloudflare deployment itself is decommissioned
separately by the maintainers, outside this repo.
