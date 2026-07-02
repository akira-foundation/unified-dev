# Contributing to Unified Dev

Thanks for taking the time to contribute. This document covers how to set up the project
locally, the branch workflow we use, and what a good pull request looks like.

## Dev setup

**Prerequisites**

- [Bun](https://bun.sh) 1.x — package manager and script runner. Don't use npm/pnpm/yarn;
  `bun.lock` is the lockfile of record.
- [Rust](https://rustup.rs), stable channel, 2021 edition
- The [Tauri prerequisites](https://tauri.app/start/prerequisites/) for your OS (Xcode
  Command Line Tools on macOS)

**Getting started**

```bash
git clone https://github.com/akira-foundation/unified-dev.git
cd unified-dev
bun install
cp .env.example .env
bun run tauri dev
```

**Running tests**

```bash
bun run test              # frontend (Vitest)
cd src-tauri && cargo test  # backend (Rust)
```

Both suites are expected to pass before you open a PR. A change that touches Rust code
should also pass `cargo clippy` and `cargo build` cleanly (no new warnings); a change
that touches TypeScript should pass `bunx tsc --noEmit` (the project builds with
`noUnusedLocals`/`noUnusedParameters` on, so unused imports are compile errors, not just
lint warnings).

## Branch workflow

This repo uses a milestone-branch gitflow. The rules, in order:

1. **Never commit directly to `main`.** `main` only receives merges via pull request.
2. Work happens in the ordinary milestone-branch flow: features branch from the current
   `milestone/vX.Y.Z` integration branch, target that branch with their PR, and the
   milestone branch merges to `main` once the whole milestone is done — **or**, for
   small, independent fixes, a `fix/<slug>` or `feat/<slug>` branch off `main` that
   targets `main` directly is fine. Check what the maintainers are doing for the current
   cycle if you're unsure which applies.
3. Branch names are descriptive kebab-case, prefixed by type: `fix/`, `feat/`, `chore/`,
   `docs/`, `refactor/`, `test/`.
4. Commits follow [Conventional Commits](https://www.conventionalcommits.org/):
   `type(scope): description`. Allowed types: `feat`, `fix`, `chore`, `docs`, `style`,
   `refactor`, `perf`, `test`, `build`, `ci`, `revert`.

## Code standards

- **Rust**: `cargo fmt` for formatting (note: `cargo fmt` reformats the whole crate via
  the module graph, not just the files you touched — check your diff before committing
  so you don't pull in unrelated reformatting). `cargo clippy` clean. Prefer early
  returns / `let-else` over nested `if`/`else` chains.
- **TypeScript/React**: named exports, no `any`, `noUnusedLocals`/`noUnusedParameters`
  enforced by `tsconfig.json`. Match the existing component structure under
  `src/components/`.
- **Comments**: keep them rare. Code should read as self-documenting through naming; a
  comment is for a non-obvious constraint or workaround, not a restatement of what the
  next line does.
- **Tests**: a behavior change ships with a test that would fail without it. Rust tests
  live next to the code in `#[cfg(test)] mod tests`; frontend tests are Vitest under the
  same directory as the code they cover.
- **Database migrations**: additive by default (`src-tauri/src/database/migrations/`,
  numbered sequentially). Column/table removal is fine when the acceptance criteria
  explicitly call for it, but data in surviving columns must be verified to persist
  through the migration — see `0051_drop_paywall_columns.sql` and its accompanying test
  for the pattern.

## Pull requests

- Keep PRs scoped to one change. If you find something unrelated worth fixing while
  you're in the code, open a separate issue instead of bundling it in.
- Describe *why*, not just *what* — the diff already shows what changed.
- Link the issue the PR closes (`Closes #123`).
- CI must be green (build, test, lint) before a maintainer will review.

## Reporting bugs and requesting features

Open a [GitHub issue](../../issues/new). For bugs, include steps to reproduce, what you
expected, and what happened instead. For security vulnerabilities, do **not** open a
public issue — see [SECURITY.md](SECURITY.md).
