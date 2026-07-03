# Security

## Threat model

This is a local-first desktop app. The primary asset is the customer's own data (repo
metadata, issue/PR content, chat history, provider credentials) at rest on their own
machine, and in transit to the providers/AI backends they've configured. It is not a
multi-tenant server, so the main risks are: another local account or process reading a
customer's data, credentials leaking across accounts within the same app install, and
a compromised build/release pipeline shipping tampered binaries.

## Authentication

GitHub OAuth is the only login method - see
[domains/auth-and-sessions.md](domains/auth-and-sessions.md) for the full flow. There is
no password; the app itself never sees or stores a GitHub password, only the OAuth
access/refresh tokens issued after the browser-based consent flow.

## Data at rest

- **Per-customer encrypted SQLite** (SQLCipher via `sqlx`), one file per logged-in
 account. A stolen file from account A cannot be opened as account B - see the HKDF key
 derivation formula in [domains/auth-and-sessions.md](domains/auth-and-sessions.md).
- **Master key in the OS keychain**, never written to disk in plaintext.
- **Provider credentials** (PAT, OAuth tokens, GitHub App installation tokens,
 Bitbucket app passwords) are stored inside that same encrypted per-customer database
 (`providers.auth_payload`), so they inherit the same at-rest protection - see
 [domains/providers.md](domains/providers.md).
- **Exception**: MCP server access tokens (`mcp_servers.access_token`) are stored in
 **plaintext** in the database, not additionally encrypted - see
 [domains/skills-and-mcp.md](domains/skills-and-mcp.md). Since the containing DB file
 is itself SQLCipher-encrypted, this is "encrypted at the file level, unencrypted
 within it" - weaker than provider credentials but not plaintext-on-disk.

## Cross-account isolation

Fixed as of the v0.12.6 per-customer isolation epic: separate DB files per customer, a
keychain-stored active-customer pointer (not derivable from any DB), and an explicit
`clear_installation_caches()` call on logout that wipes the in-memory GitHub App
installation-token cache. That last one closed a real vulnerability (issues #184-186):
before the fix, a second customer sharing a GitHub org with the first could receive the
first customer's cached installation token within a 5-minute TTL window after an
account switch. See [domains/auth-and-sessions.md](domains/auth-and-sessions.md) for the
full root-cause writeup.

## Remote host exposure

The embedded remote-pairing HTTP server (see
[domains/remote-host.md](domains/remote-host.md)) is the one network-facing surface that
accepts unauthenticated requests at all (`/remote/health`, `/remote/auth/pair`). Two
known weaknesses, documented here rather than silently left implicit:

- The pairing code's `pairing_code_expires_at` column is set but never checked - a
 generated pairing code does not actually expire.
- Device auth tokens are compared by direct string equality against
 `remote_devices.token_hash`, despite the column name implying a hash - the value
 stored is the plaintext token.

Binding defaults to `127.0.0.1` (loopback only); a `tailscale_required` setting exists
for exposing it beyond loopback, but no route handler currently enforces that flag, so
if the port is reachable at all (e.g. bound to `0.0.0.0` by user configuration), the
pairing code and token checks above are the only gates.

## Build/release integrity

- Update artifacts are signed with `TAURI_SIGNING_PRIVATE_KEY` (CI secret only) and
 verified client-side against the `pubkey` in `tauri.conf.json` before an update is
 applied.
- macOS builds are Apple-notarized and codesigned in CI (`build-and-release.yml`) using
 a certificate imported into a throwaway CI keychain per run.
- **Local builds are unsigned** - running a locally-built binary against the same
 keychain entries as an installed, properly-signed release can corrupt keychain ACLs
 for the real app, since macOS ties keychain access to the binary's code signature.
 Never run a locally-built binary against production keychain data; use a separate
 `.env`/profile for local development. See [08-troubleshooting.md](08-troubleshooting.md).

## Reporting a vulnerability

See [SECURITY.md](../SECURITY.md) - private GitHub Security Advisory disclosure, not a
public issue.
