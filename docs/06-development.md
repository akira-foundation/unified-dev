# Development

## Prerequisites

- [Bun](https://bun.sh) 1.x - the only supported package manager (`bun.lock` is the
 lockfile of record; do not generate `pnpm-lock.yaml`/`package-lock.json`).
- Rust, stable channel, 2021 edition.
- [Tauri prerequisites](https://tauri.app/start/prerequisites/) for your OS (Xcode
 Command Line Tools on macOS).

## Getting started

```bash
git clone https://github.com/akira-foundation/unified-dev.git
cd unified-dev
bun install
cp .env.example .env
bun run tauri dev
```

`AKIRA_BILLING_URL` and `AKIRA_BILLING_SECRET` in `.env` are required for GitHub login
to work locally - see [04-configuration.md](04-configuration.md). Without them, the app
runs but login fails with `bad_signature` (empty secret compiled in via `env!()`).

## Scripts (`package.json`)

| Script | Purpose |
|---|---|
| `bun run dev` | Vite dev server only (frontend, no Tauri shell). |
| `bun run desktop` | `tauri dev` - the actual native app, hot-reloading both frontend and Rust changes. |
| `bun run build` | `tsc && vite build` - frontend production build (type-checks first). |
| `bun run test` | Vitest, frontend unit tests. |
| `bun run test:watch` | Vitest watch mode. |

Backend tests run separately: `cd src-tauri && cargo test`.

## Running tests

```bash
bun run test        # frontend
cd src-tauri && cargo test  # backend
```

Both are expected to pass before opening a PR. Rust changes should also pass
`cargo clippy` and `cargo build` with no new warnings; TypeScript changes should pass
`bunx tsc --noEmit` - `noUnusedLocals`/`noUnusedParameters` are enabled, so an unused
import is a compile error, not a lint warning.

## Branch workflow

Milestone-branch gitflow:

1. Never commit directly to `main` - only merges via PR.
2. Larger, coordinated work: feature branches off the current `milestone/vX.Y.Z`
  integration branch, PR into that branch; the milestone branch merges to `main` once
  the whole milestone is done. Small, independent fixes: a `fix/`/`feat/` branch off
  `main`, PR straight to `main`.
3. Branch names: kebab-case, prefixed by type (`fix/`, `feat/`, `chore/`, `docs/`,
  `refactor/`, `test/`).
4. Commits follow [Conventional Commits](https://www.conventionalcommits.org/):
  `type(scope): description`. Types: `feat`, `fix`, `chore`, `docs`, `style`,
  `refactor`, `perf`, `test`, `build`, `ci`, `revert`.

## Code standards

- **Rust**: `cargo fmt`, `cargo clippy` clean. Note: `cargo fmt` reformats the whole
 crate via the module graph regardless of which files you pass it - always check
 `git diff --name-only` after running it and revert unrelated files before committing.
 Prefer early returns / `let-else` over nested `if`/`else` chains.
- **TypeScript/React**: named exports only, no `any`. Match existing component
 structure under `src/components/`.
- **Comments**: rare, by design. A comment is for a non-obvious constraint or
 workaround, not a restatement of the next line.
- **Tests**: a behavior change ships with a test that would fail without it. Rust tests
 live in `#[cfg(test)] mod tests` next to the code; frontend tests are Vitest files
 beside the code they cover.
- **Database migrations**: additive by default, numbered sequentially under
 `src-tauri/src/database/migrations/`. Column/table removal is acceptable when the
 task explicitly calls for it, but any surviving-column data must be verified to
 persist through the migration (see `0051_drop_paywall_columns.sql` and its test for
 the pattern).

## Debugging

- **Rust logs**: `tauri dev` prints backend `eprintln!`/`tracing` output directly to
 the terminal running it.
- **Frontend**: standard browser devtools inside the Tauri webview (right-click →
 Inspect, or the Tauri dev menu).
- **Database inspection**: DB files are SQLCipher-encrypted - a plain `sqlite3` CLI
 cannot open them without the customer's derived key. Use `sqlcipher` with
 `PRAGMA key = "x'<hex>'"` (see [domains/auth-and-sessions.md](domains/auth-and-sessions.md)
 for the derivation formula) if you need to inspect a local DB file directly.

## Pull requests

- Scope one change per PR - file a separate issue for unrelated things noticed along
 the way.
- Explain *why*, not *what* - the diff already shows what changed.
- Link the issue closed (`Closes #123`).
- CI (build, test, lint) must be green before review.

## Reporting bugs / requesting features

Open a [GitHub issue](https://github.com/akira-foundation/unified-dev/issues/new) with
repro steps, expected vs. actual behavior. For security vulnerabilities, do not open a
public issue - see [05-security.md](05-security.md).
