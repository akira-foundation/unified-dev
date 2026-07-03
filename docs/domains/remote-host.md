# Remote Host

## Purpose

An embedded axum HTTP server (`src-tauri/src/app/remote/`), started per the app's
settings, lets a phone or browser pair with the running desktop app and drive/read agent
threads remotely: list repos, send a chat message, poll for the response, abort a run,
view git changes, view PR status.

## Pairing

`regenerate_pairing_code()` (`app/settings/remote.rs`) generates a code like
`UNFD-XXXX` (`random_code("UNFD-", 4)`), stored in `remote_settings.pairing_code` with
`pairing_code_expires_at` set to now + 10 minutes.

`POST /remote/auth/pair` (`app/remote/pair.rs`) validates by plain string comparison
against the stored code.

**Known gap**: `pairing_code_expires_at` is written on generation but never read back
anywhere in `app/remote/` - the expiry column exists in the schema but nothing enforces
it, so a generated pairing code does not actually expire after 10 minutes despite the
column's name and the UI's implication.

## Auth (post-pairing)

Every route except `/remote/health` and `/remote/auth/pair` requires a Bearer token in
the `Authorization` header, checked by `authorize()` (`app/remote/support.rs`) - a
direct match against `remote_devices.token_hash` where `revoked_at IS NULL`.

**Known gap**: despite the column name `token_hash`, the stored value is compared
directly (plaintext), not hashed.

## Routes

```
GET /remote/health
POST /remote/auth/pair
GET /remote/repositories
GET /remote/threads/{thread_id}/messages
POST /remote/threads/{thread_id}/messages
POST /remote/threads/{thread_id}/abort
GET /remote/threads/{thread_id}/changes
GET /remote/threads/{thread_id}/pr
```

## Message flow is poll-based, not streamed

There is no SSE, WebSocket, or streaming transport on the remote HTTP server (unlike the
in-app chat UI, which streams tokens over Tauri events - see
[ai-agents-and-chat.md](ai-agents-and-chat.md)). `POST .../messages` fires the agent run
in the background and returns `{accepted: true}` immediately; the remote client is
expected to poll `GET .../messages`, which returns the full message list every time.

## Shared state, not isolated

The remote server runs in the same process as the desktop app and shares its
`SqlitePool` and the same abort-handle map used by the native agent runner - a message
sent from a paired phone and a message typed in the desktop UI are indistinguishable to
the backend; both hit the same thread, same DB, same abort mechanism.

## Networking

Binds to `{bind_address}:{port}` from settings (default `127.0.0.1:4280`). No local
network discovery (mDNS/Bonjour) is implemented. A `tailscale_required` setting column
exists, implying the intended deployment model is over a Tailscale tailnet rather than
raw LAN exposure, but no route handler currently enforces it - reaching the port at all
is sufficient if the pairing code and token checks pass.
