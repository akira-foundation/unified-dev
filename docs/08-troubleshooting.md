# Troubleshooting

## `internal error: bad_signature` on GitHub login

**Cause**: `AKIRA_BILLING_SECRET` is compiled into the binary at build time via
`env!()` (`src-tauri/src/app/billing/client.rs`). If no `.env` file exists (or the
variable is empty) when `cargo build`/`tauri dev` runs, the binary bakes in an empty
secret, and the HMAC-signed request to `AKIRA_BILLING_URL` is rejected by the billing
backend.

**Fix**: ensure `.env` exists at the repo root with a real `AKIRA_BILLING_SECRET`
before building - copying `.env` and just restarting the already-running dev process is
not enough, since the value is baked in at compile time, not read at runtime. Kill the
running `tauri dev` process and restart it after `.env` is in place.

## macOS "Malware Blocked" dialog on a locally-built binary

**Cause**: local dev builds are unsigned (CI-only codesigning/notarization - see
[07-operations.md](07-operations.md)). Gatekeeper flags unsigned/unnotarized binaries
downloaded or run outside a signed context.

**Fix**: this is expected for local builds; either allow it via System
Settings → Privacy & Security, or build with a valid Apple signing identity locally if
you need a signed artifact.

## Running a local build corrupts the installed app's login

**Cause**: macOS keychain access control is tied to the binary's code signature. A
locally-built (differently-signed, or unsigned) binary that touches the same keychain
entries (`unified-dev` service, `db-master-key`/`token-encryption-key`/
`active-customer`) as the properly-signed installed app can rewrite the keychain ACL,
breaking the installed app's ability to decrypt its own stored tokens on next launch.

**Fix**: never run a locally-built binary against the same machine/keychain as a
production install you care about. Use a separate test machine, a separate OS user, or
accept that local dev builds and the installed release app will fight over the same
keychain entries.

## Autopilot job stuck on "running" after restarting the app

**Cause**: job orchestration is frontend-owned (`useAutopilotStore.ts`), not a backend
daemon - see [domains/autopilot.md](domains/autopilot.md). If the app is closed mid-job,
the in-memory loop simply stops; the job row is left at `status = "running"` in the
database because nothing set it to `"failed"`/`"completed"` on the way out.

**Fix**: reopening the app does not currently auto-resume the job. Cancel/delete the
stuck job from the Autopilot panel and start a new one if needed.

## Open Source insights dashboard is empty or stale

**Cause**: sync is manual-only - there is no automatic sync on login or on a timer (see
[domains/open-source-insights.md](domains/open-source-insights.md)). If the last sync
failed silently (e.g. rate-limited, or a GitHub App installation with no per-user OAuth
token - surfaced as `GithubAppNoUserTokenState`), the dashboard just shows old data.

**Fix**: click the sync button; check for a rate-limit or "no user token" state banner
on the page.

## Provider operation fails with "not supported"

**Cause**: `VcsProvider` methods are not all mandatory per driver (see
[domains/providers.md](domains/providers.md)) - optional operations default to a "not
supported" error if the specific provider driver (GitHub/GitLab/Bitbucket) hasn't
implemented them.

**Fix**: check which driver the org's provider is using; the operation may genuinely be
unavailable for that provider rather than a bug.

## Build fails with "No space left on device" during `cargo build`

**Cause**: Rust build artifacts under `target/` accumulate quickly across multiple
worktrees/branches and can fill disk.

**Fix**: `cargo clean` from `src-tauri/` to reclaim space (can free double-digit GB on a
long-lived checkout).
