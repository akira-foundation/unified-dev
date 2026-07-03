# Configuration

## Environment variables

`.env.example` (copy to `.env` for local dev - `bun run tauri dev` reads it via Tauri's
build-time env loading):

```
ANTHROPIC_API_KEY=
OPENAI_API_KEY=
OLLAMA_HOST=

AKIRA_BILLING_URL=https://billing.test
AKIRA_BILLING_SECRET=<hmac_secret do product>
```

| Variable | Required | Purpose |
|---|---|---|
| `ANTHROPIC_API_KEY` | No | Enables the Claude provider if the `claude` CLI isn't installed/signed in. See [domains/ai-agents-and-chat.md](domains/ai-agents-and-chat.md) for the detection order. |
| `OPENAI_API_KEY` | No | Enables the OpenAI/Codex provider. |
| `OLLAMA_HOST` | No | Points at a local Ollama server to enable local-model chat. |
| `AKIRA_BILLING_URL` | **Yes** | Base URL of the external billing backend used for GitHub OAuth code exchange and anonymous usage counting. Without it, login fails outright - see [08-troubleshooting.md](08-troubleshooting.md). |
| `AKIRA_BILLING_SECRET` | **Yes** | HMAC secret used to sign requests to `AKIRA_BILLING_URL`. Baked in at Rust **compile time** via `env!()` (`app/billing/client.rs`) - changing it requires a rebuild, not just editing `.env` and restarting. |

None of the AI provider keys are required to run the app - with all three empty and no
CLI/local tools detected, the app still runs; the agent picker just has no models
available until a provider is configured.

## Config directories

- App data (per-customer encrypted DBs, installed skills): platform-standard Tauri
 `app_data_dir`, under an `Unified/` subfolder, then `<customer_id>/`.
- OS keychain (service `unified-dev`): `db-master-key`, `token-encryption-key`,
 `active-customer` pointer. See [05-security.md](05-security.md).

## Runtime settings (in-app, DB-persisted, not env vars)

Stored in the customer's own database, editable from the Settings page - not
environment configuration, but worth distinguishing from the `.env` vars above since
both are sometimes called "config":

- Appearance (theme, locale) - `settings-store.ts` / `settings` table.
- Sync intervals per scope (issues/PRs/repos/orgs) - `sync-settings-store.ts`.
- Remote host bind address/port, pairing code, Tailscale requirement flag - see
 [domains/remote-host.md](domains/remote-host.md).
- MCP server URLs/tokens, enabled skills - see
 [domains/skills-and-mcp.md](domains/skills-and-mcp.md).

## Auto-updater configuration

`src-tauri/tauri.conf.json`'s `updater` block:

```json
"updater": {
 "endpoints": [
  "https://github.com/akira-foundation/unified-dev/releases/latest/download/latest.json"
 ],
 "pubkey": "..."
}
```

Points at the GitHub Releases "latest" endpoint (replaced a DigitalOcean Spaces CDN
endpoint in v0.12.7 - see [07-operations.md](07-operations.md)). `pubkey` is the
minisign public key used to verify the signature on downloaded update artifacts against
`TAURI_SIGNING_PRIVATE_KEY` (held only in CI secrets, never in the repo).
