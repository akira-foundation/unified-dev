# Per-customer database isolation plan

One encrypted SQLite file per customer at `app_data_dir/Unified/<customer_id>/unified.db`.
The whole file is encrypted with a per-customer key derived from a keychain master key. The
connection pool is swapped at login/logout. A file stolen from account A cannot be opened
under account B.

## Decisions (locked)

- **Encryption**: whole-DB SQLCipher with a per-customer derived key.
- **Existing shared DB**: migrate-on-first-login split into the per-customer file.
- **Control plane**: active-customer pointer lives in the OS keychain (no control-plane DB).

## Core problem

Today `customer_id` lives *inside* the DB (`license` row `id='local'`,
`src-tauri/src/app/auth/mod.rs:9`). The per-customer path needs `customer_id` *before* opening
any DB, so this is a chicken-and-egg dependency. Fix: move the **active-customer pointer** to
the OS keychain. The session token stays inside the per-customer DB and is read after the DB
opens. Only the pointer must escape the data file.

## On-disk layout

```
app_data_dir/
  Unified/
    <customer_id>/
      unified.db          # SQLCipher-encrypted
      unified.db-wal
      unified.db-shm
  unified-dev.sqlite      # legacy shared DB (renamed .migrated after split)
  dev-key.txt             # debug only (existing)
```

Keychain (`service = "unified-dev"`):

- `token-encryption-key` — existing field cipher key (keep).
- `db-master-key` — new, 32 bytes, root for deriving per-customer DB keys.
- `active-customer` — new, holds the logged-in `customer_id`. Absence means logged out.

## Crypto design

Per-customer DB key, derived not stored:

```
db_key(customer_id) = HKDF-SHA256(
    ikm  = db_master_key,            // from keychain
    salt = customer_id bytes,
    info = "unified-dev/db-key/v1"
) -> 32 bytes -> hex(64) -> PRAGMA key = "x'<hex>'"
```

Raw-key format (`x'...'`, 64 hex) makes SQLCipher use the key directly with a random per-file
salt in the header. No master key sits on disk in plaintext. Different `customer_id` yields a
different key, so file A will not decrypt under B. `db-master-key` is created once via the
existing `KeyStore::load_or_create_key` pattern (`src-tauri/src/app/support/security/key_store.rs:12`)
under a new account constant.

## Dependency change (verify first)

`sqlx` plain SQLite must become SQLCipher-backed. Add a direct dep so cargo unifies the
feature across `sqlx-sqlite`'s `libsqlite3-sys`:

```toml
libsqlite3-sys = { version = "*", features = ["bundled-sqlcipher-vendored-openssl"] }
```

Pragma order matters: `key` must be the first statement on the connection, before
`journal_mode`. Confirm `SqliteConnectOptions::pragma("key", ...)` is emitted before
`.journal_mode(WAL)`; if sqlx ordering is wrong, set both via an `after_connect` hook
(`PRAGMA key` then `PRAGMA journal_mode=WAL`).

## Phase 0 — spike (gate)

1. Add `libsqlite3-sys` dep, build on macOS.
2. Throwaway test: open an encrypted file, write a row, reopen with the wrong key (expect
   failure), reopen with the right key (expect the row back).
3. Confirm WAL and SQLCipher coexist, and that `sqlcipher_export()` is available (needed by
   Phase 5).

Decision point: proceed with sqlx, or switch the data layer to `rusqlite` with
`bundled-sqlcipher`.

## Phase 1 — swappable pool

Today `AppState.db_pool: SqlitePool` is set once (`src-tauri/src/state/app_state.rs:17`) and
referenced everywhere as `state.db_pool` / `app_state.db_pool`.

- `db_pool: SqlitePool` becomes `db: Arc<RwLock<Option<SqlitePool>>>` (logged-out = `None`).
- Add `AppState::pool() -> AppResult<SqlitePool>`: clones the pool out of the lock, returns a
  new `AppError::Unauthenticated` when `None`. `SqlitePool` clone is cheap (Arc inside).
- Add `set_pool(pool)` / `clear_pool()` for the login/logout swap.
- `license_gate` (`src-tauri/src/state/app_state.rs:21,30`) binds a fixed pool at construction;
  make it resolve the pool lazily, or rebuild it on each swap. Same for anything caching a
  pool clone.
- Mechanical sweep: every `&state.db_pool` / `&app_state.db_pool` becomes `&state.pool().await?`.
  Touches the files already in the diff (open_source/*, providers/*, orgs/*, projects/*,
  tracker/*, settings/poller.rs, license/gate.rs) plus setup.rs.
- New `AppError::Unauthenticated` maps to a frontend logged-out state instead of a crash.

## Phase 2 — DB module: per-customer open + keychain pointer

In `src-tauri/src/database/mod.rs`:

- `customer_db_path(app, customer_id) -> PathBuf` returns
  `app_data_dir/Unified/<customer_id>/unified.db` (`create_dir_all`). Keep the debug tag suffix.
- `open_customer_pool(app, customer_id) -> SqlitePool`: derive key,
  `SqliteConnectOptions.filename(path).create_if_missing(true).foreign_keys(true)
  .pragma("key", x'..').journal_mode(WAL)`, then `sqlx::migrate!` (existing line 39, full set
  per DB).
- New `app/support/security` helpers: `derive_db_key(customer_id)` (HKDF),
  `db_master_key()` (keychain load-or-create).
- New keychain pointer module: `active_customer_get/set/clear`, reusing the `TokenKeyring` /
  onyx-rs shell-out convention.

## Phase 3 — login flow

`src-tauri/src/app/auth/oauth.rs` `persist_customer_session` (~188) runs while logged out (no
pool yet). New order:

1. OAuth exchange yields `customer_id`, email, token (unchanged).
2. `pool = open_customer_pool(app, customer_id)` (creates + migrates on first use).
3. Legacy split (Phase 5) if applicable.
4. `state.set_pool(pool)`.
5. Persist the session into the per-customer DB license row (`id='local'`, customer_id = this
   customer) via the existing UPSERT, now against the new pool.
6. `active_customer_set(customer_id)` in the keychain.
7. (Re)start pollers + remote bound to the new pool (Phase 6).

## Phase 4 — logout flow

`src-tauri/src/app/auth/logout.rs`:

1. `billing.clear_customer_token()` (keep).
2. Stop pollers/remote (abort_handles).
3. `state.clear_pool()` (drops the pool, closes connections).
4. `active_customer_clear()` in the keychain.
5. Do not delete the DB file; data persists for the next login.

Drop the current `UPDATE license SET ... NULL`; the whole DB is simply detached now.

## Phase 5 — migrate-on-first-login split (one-time)

On login, before `set_pool`, if legacy `unified-dev.sqlite` exists AND no
`Unified/<customer_id>/unified.db` yet AND legacy `license.customer_id == customer_id`:

- Open legacy plaintext (`PRAGMA key=''`), `ATTACH` the new encrypted DB with its key,
  `SELECT sqlcipher_export('encrypted')`, `DETACH`.
- Rename legacy to `unified-dev.sqlite.migrated` (keep as backup, do not delete).
- If legacy `customer_id` is null or differs, skip and start a fresh DB.

`sqlcipher_export` is the canonical plaintext-to-encrypted copy; confirm availability in the
bundled build during Phase 0.

## Phase 6 — boot sequence

`src-tauri/src/setup.rs:15-66`:

- Open no DB eagerly. Read `active-customer` from the keychain.
  - Present: `open_customer_pool`, `set_pool`, load the customer token from that DB
    (`src-tauri/src/setup.rs:26`), bootstrap the envelope, start remote/poller.
  - Absent: logged-out — `set_pool(None)`, skip token load, skip poller/remote; the frontend
    shows login.
- `app.manage(AppState::new(...))` constructs with `db: None`; the branch above fills the pool.
- Poller/remote start becomes a reusable fn called both here and at login (Phase 3 step 7).

## Phase 7 — customer_scope columns (0044-0046)

Keep them. In a single-customer-per-file DB they are redundant but harmless; leaving the
`WHERE customer_id = ?` filters in place is defense-in-depth and avoids churn across the diff.
`current_customer_id()` (`src-tauri/src/app/auth/mod.rs:9`) still reads the active DB's license
row, so it always matches. No new migration to drop them.

## Testing

- Unit: `derive_db_key` deterministic per customer_id, differs across ids; wrong key fails to
  open (asserted in Phase 0).
- Integration: login A, write data, logout, login B — B sees its own/empty DB while A's file
  exists but is A-keyed. Re-login A — data intact.
- Migration: seed a legacy plaintext DB for customer X, first login X — data appears in the
  encrypted per-customer DB, legacy renamed `.migrated`.
- Logged-out boot: no keychain pointer — app boots, commands return Unauthenticated, no panic.
- WAL: confirm `-wal` / `-shm` land under `Unified/<id>/`.

## Risks

1. SQLCipher + sqlx linkage — highest; gated by Phase 0, fallback `rusqlite`.
2. Pragma ordering — key before journal_mode; use an after_connect hook if needed.
3. Pool-swap races — in-flight queries on an old pool clone during logout; stop pollers/remote
   before `clear_pool`, keep command pool clones short-lived.
4. Keychain ACL — a different code signature rewrites the macOS ACL and breaks decryption; do
   not run dev binaries against the prod keychain.
5. Build size / OpenSSL vendoring — `bundled-sqlcipher-vendored-openssl` adds build time;
   verify the desktop-release pipeline still builds.

## Rollout order

Phase 0 (spike) -> 1 (swappable pool) -> 2 (db module) -> 6 (boot, logged-out path) ->
3 + 4 (login/logout) -> 5 (legacy split) -> 7 (leave scope) -> tests throughout.
