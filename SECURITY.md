# Security Policy

## Reporting a vulnerability

**Do not open a public GitHub issue for a security vulnerability.**

Report it privately through GitHub's built-in disclosure channel:

1. Go to the [Security tab](../../security) of this repository.
2. Click **Report a vulnerability**.
3. Describe the issue: what it is, how to reproduce it, and its impact.

This opens a private advisory visible only to you and the maintainers, so we can discuss
and fix the issue before any public disclosure. You'll get a response acknowledging the
report, and we'll keep you updated as we investigate and patch.

If you're unable to use GitHub's reporting flow for any reason, open a regular issue
asking a maintainer to reach out on a private channel — without any vulnerability
details in the issue itself.

## Scope

Unified Dev is a local-first desktop app: your repositories, issues, and agent sessions
are stored in a SQLCipher-encrypted SQLite database on your machine, keyed per logged-in
account. Security reports that are especially useful to us:

- Anything that could let one logged-in account read or write another account's local
  data (see `src-tauri/src/database/`, `src-tauri/src/app/support/security/`)
- Credential or token handling issues (OAuth flow in `src-tauri/src/app/auth/`, token
  encryption in `src-tauri/src/app/support/security/`)
- Supply-chain concerns in the build/release pipeline
  (`.github/workflows/build-and-release.yml`)

## Supported versions

Only the latest released version is supported with security fixes. The app auto-updates,
so most installs stay current automatically.
