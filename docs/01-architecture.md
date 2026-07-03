# Architecture

## High-level shape

```
┌─────────────────────────────┐    Tauri IPC (invoke/emit)    ┌──────────────────────────────┐
│ Frontend (src/)       │ ─────────────────────────────────────▶│ Backend (src-tauri/)     │
│ React + TypeScript + Vite  │◀───────────────────────────────────── │ Rust + Tauri 2        │
└─────────────────────────────┘                    └──────────────────────────────┘
                                           │
                                           ▼
                                    ┌────────────────────────────┐
                                    │ Per-customer SQLite DB    │
                                    │ (SQLCipher-encrypted, sqlx) │
                                    └────────────────────────────┘
                                           │
               ┌──────────────────────────────────────────────────────┼──────────────────────────┐
               ▼                           ▼             ▼
         GitHub / GitLab / Bitbucket               Linear / Jira        AI provider
            REST/GraphQL APIs                 (via `tracker`)     APIs/CLIs (Claude,
                                                  OpenAI, Gemini, Ollama,
                                                    Copilot)
```

There is a fourth external dependency not in the diagram: a small billing backend
(`AKIRA_BILLING_URL`) used only for GitHub OAuth code exchange and anonymous usage
counting. It is not part of the app's own data path.

## Frontend ↔ backend communication

The frontend never talks to the network or filesystem directly for app data - every
action goes through a Tauri **command** (`#[tauri::command]` in Rust, called via
`invoke("command_name", args)` from TypeScript). Long-running/streaming operations (chat
tokens, sync progress) use Tauri **events** (`emit`/`listen`) instead of a single
request/response.

Commands are registered in `src-tauri/src/lib.rs`'s `generate_handler!` macro and live
under `src-tauri/src/commands/`, which are thin wrappers that delegate to the actual logic
in `src-tauri/src/app/<domain>/`.

## AppState

`src-tauri/src/state/app_state.rs` defines `AppState`, the single piece of shared state
every Tauri command receives via `tauri::State<AppState>`. Notably:

- `db: Arc<RwLock<Option<SqlitePool>>>` - the database connection pool. It's an `Option`
 because the app can be in a **logged-out state** with no pool at all; `AppState::pool()`
 returns `AppError::Unauthenticated` in that case instead of panicking. The pool is
 swapped (not just replaced) on login/logout - see
 [domains/auth-and-sessions.md](domains/auth-and-sessions.md).
- `billing: Arc<RwLock<BillingClient>>` - the client for the external billing backend
 (OAuth exchange, usage counting).
- `provider_factory`, `tracker_registry` - factories for VCS and issue-tracker drivers.
- `abort_handles` - in-flight background task handles (chat sessions, sync jobs) keyed by
 ID, so they can be cancelled.

## Data layer

- **One encrypted SQLite file per customer**, at `app_data_dir/Unified/<customer_id>/unified.db`.
 A file stolen from one account cannot be opened under another - see
 [05-security.md](05-security.md) for the full threat model and crypto design.
- **Migrations** live in `src-tauri/src/database/migrations/` (51 as of this writing),
 run via `sqlx::migrate!` on every pool open - fresh installs and upgrades both end on
 the same schema.
- Most domain tables carry a `customer_id` column as defense-in-depth even though the
 per-file encryption already isolates accounts (kept intentionally - see the "Phase 7"
 decision in the per-customer isolation epic).

## Directory structure

```
src/             # React frontend
 pages/           # one file per top-level route
 components/         # feature components (agents/, settings/, open-source/, ...)
 stores/           # Zustand state stores
 hooks/           # reusable React hooks
 i18n/            # translations, organized by topic (see docs/03-frontend.md)
 services/          # thin invoke() wrappers grouped by domain

src-tauri/src/
 app/            # domain logic, one folder per bounded context
  auth/           # GitHub OAuth login/logout
  support/security/     # encryption, keychain, HKDF key derivation
  providers/        # VCS provider CRUD + credential management
  orgs/, repos/       # organizations, local/remote repositories
  issues/          # issue sync + CRUD
  chat/           # AI chat session orchestration
  autopilot/        # unattended multi-issue job runner
  skills/, mcp/       # agent extensibility
  projects/         # kanban boards
  remote/          # embedded HTTP server for phone/browser pairing
  open_source/       # GitHub contribution insights
  settings/, notifications/ # app configuration, in-app notification center
 commands/          # #[tauri::command] entry points (thin wrappers)
 providers/         # VcsProvider trait + GitHub/GitLab/Bitbucket drivers
 tracker/          # Tracker trait + Linear/Jira drivers (separate from providers/)
 ai/             # AI provider clients, agent detection, tool definitions
 database/          # migrations, per-customer DB open, legacy-DB migration
 state/           # AppState

worker/            # removed - see CHANGELOG; GitHub OAuth/usage now go
                # through the external billing backend directly
```

## Design principles observed in the codebase

- **Two separate provider seams, not one.** `VcsProvider` (GitHub/GitLab/Bitbucket) is
 git/repo-shaped (owner, repo, branch, PR). `Tracker` (Linear/Jira) is issue-workflow-shaped
 (status, team, cycle). They were kept apart deliberately so one abstraction doesn't have
 to bend to fit both - see [domains/tracker.md](domains/tracker.md).
- **Local-first, sync-on-demand.** Issues, PRs, and contribution stats are cached in
 SQLite and refreshed by explicit sync calls or a background poller - the app is usable
 offline against the last-synced data.
- **Commands stay thin.** `src-tauri/src/commands/*.rs` files are argument/error-shape
 adapters; the actual logic lives in `app/<domain>/`, which is directly unit-testable
 without a Tauri runtime.
