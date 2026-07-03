# Auth & Sessions

## Login

GitHub OAuth is the only login path (`src-tauri/src/app/auth/oauth.rs`). There is no
password or email/OTP login - that flow existed for license activation and was removed
along with the paywall (v0.12.7).

`login_with_provider`:

1. Binds an ephemeral loopback TCP listener, opens the system browser to the billing
  backend's OAuth init URL (`AKIRA_BILLING_URL`), and waits for the redirect callback
  carrying an authorization code.
2. Exchanges the code via the `akira_billing` SDK, which talks to `AKIRA_BILLING_URL` - 
  this is the only network call involved in login; the app never touches a Cloudflare
  Worker or third-party OAuth endpoint directly.
3. `database::migrate_legacy_if_needed(app, customer_id)` - one-time migration for
  installs that predate per-customer DB isolation (see below).
4. `database::open_customer_pool(app, customer_id)` - opens (or creates) that customer's
  encrypted SQLite file and swaps it into `AppState` via `state.set_pool(pool)`.
5. Persists the session (`customer_id`, `customer_email`, an encrypted `customer_token_cipher`)
  into the new pool's `license` table (`id = 'local'`) - see `app/license/session.rs`.
6. `active_customer_set(customer_id)` writes the logged-in customer's ID to the OS
  keychain.
7. `setup::start_background_services(app, pool)` starts the remote host (if enabled) and
  the sync poller bound to the fresh pool.

## Logout

`app/auth/logout.rs`:

1. Clears the billing client's in-memory customer token.
2. Stops the remote host server.
3. `clear_installation_caches()` - wipes the in-memory GitHub App installation-token
  caches (see below; this is a deliberate security fix, not incidental cleanup).
4. `state.clear_pool()` - detaches the database. Data is **not deleted**, just
  disconnected; logging back in as the same customer reopens the same file.
5. Clears the `active-customer` keychain pointer.

## Per-customer database isolation

One SQLCipher-encrypted SQLite file per customer, at
`app_data_dir/Unified/<customer_id>/unified.db`. This is the structural fix for a
cross-customer data leak found in 2026-06 (issues #184-186): before this, all customers
on one machine shared a single database file, and switching accounts only wiped a handful
of tables - a stale row or a copied file could expose another account's data.

**Key derivation** (`app/support/security/db_key_store.rs`):

```
db_key(customer_id) = HKDF-SHA256(
  ikm = db_master_key,   // from OS keychain, generated once
  salt = customer_id,
  info = "unified-dev/db-key/v1"
) -> 32 bytes -> hex -> PRAGMA key = "x'<hex>'"
```

The master key never touches disk in plaintext; it lives in the OS keychain (service
`unified-dev`, account `db-master-key`), loaded via the same `KeyStore::load_or_create`
pattern used for the token-encryption key.

**Critical implementation detail**: `sqlx`'s `SqliteConnectOptions::pragma()` /
`.journal_mode()` builder methods run during connection *establishment*, before the pool's
`after_connect` hook. If `PRAGMA key` is set via the builder instead of inside
`after_connect`, it races other pragmas and corrupts the file on reopen. Every place that
opens an encrypted connection in this codebase sets `PRAGMA key` as the *first* statement
inside `after_connect`, then `journal_mode`/`foreign_keys` after it. This was discovered
during a Phase-0 spike (#189) specifically to gate the sqlx-vs-rusqlite decision before
building the rest of the isolation epic.

**Active-customer pointer**: which customer is logged in lives in the keychain
(`active-customer` account), not in any database - this breaks the chicken-and-egg problem
of needing to know the customer ID before you can open their DB.

**Boot sequence** (`setup.rs`): reads the `active-customer` keychain entry.
Present → open that customer's pool, load their session, start background services.
Absent → `AppState` is constructed with no pool at all; any command that needs the
database gets `AppError::Unauthenticated` instead of a panic, and the frontend shows the
login screen.

**Legacy migration** (`database/legacy_migration.rs`): on first login after upgrading from
a pre-isolation install, if the old shared `unified-dev.sqlite` exists, the per-customer
file doesn't exist yet, and the legacy DB's `license.customer_id` matches the customer
logging in, the legacy plaintext DB is copied into the new encrypted file via SQLCipher's
`sqlcipher_export()`, then renamed to `unified-dev.sqlite.migrated` (kept as a backup,
never deleted).

## GitHub installation-token cache (cross-customer leak, fixed)

`app/orgs/resolve_provider.rs` caches GitHub App installation tokens
(`INSTALLATION_TOKEN_CACHE`) keyed only by `installation_id` - which is an
organization-level identifier, not customer-level. Because this is a single-process
desktop app, switching GitHub accounts happens via logout → login, not via separate OS
processes. If two customers on the same machine both have access to the same GitHub org
(same `installation_id`), customer B could, within the 5-minute cache TTL, receive an
installation token minted for customer A's session.

Fixed by clearing both `INSTALLATION_TOKEN_CACHE` and `INSTALLATIONS_CACHE` on every
logout (`clear_installation_caches()`, called from `app/auth/logout.rs`), so a fresh
login always starts cold.

## Session token storage

`app/license/session.rs` (the only surviving piece of the old `app/license/` module after
the paywall was removed) holds `load_customer_token` / `clear_customer_token` - reads and
writes the encrypted GitHub session token in the `license` table's `customer_token_cipher`
column. The `license` table itself only tracks `id`, `customer_id`, `customer_email`,
`customer_token_cipher` - every plan/billing/signature column was dropped in the v0.12.7
paywall removal (migration `0051_drop_paywall_columns.sql`).
