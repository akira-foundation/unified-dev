# FAQ

### Why does this app need a billing backend if it's free/open source?

`AKIRA_BILLING_URL` is used only for two things: exchanging the GitHub OAuth code
during login, and anonymous usage counting. It is not a paywall - the v0.12.7
transition removed all license/plan/paywall gating from the app entirely, but this one
endpoint was kept as the mechanism for the OAuth handshake and for aggregate adoption
metrics.

See [domains/ai-agents-and-chat.md](domains/ai-agents-and-chat.md#usage-tracking).

### Do I need an Anthropic/OpenAI API key to use this app?

No. If you have the `claude` CLI installed and signed in, or the GitHub Copilot CLI
configured, or a local Ollama server running, the app detects and uses those without
any API key in `.env`.

See the detection table in [domains/ai-agents-and-chat.md](domains/ai-agents-and-chat.md).

### Why are there two separate abstractions for GitHub/GitLab/Bitbucket vs. Linear/Jira instead of one unified "integration" concept?

Because they're shaped differently at the domain level. `VcsProvider` is git/repo
shaped (owner, repo, branch, PR); `Tracker` is issue-workflow shaped (status, team,
cycle, no concept of a repo). Forcing one trait to cover both would mean bending one
side to fit the other.

See [domains/providers.md](domains/providers.md) and [domains/tracker.md](domains/tracker.md).

### Is my data synced to a cloud service?

No non-provider cloud storage. Data lives in a SQLCipher-encrypted SQLite file on your
machine, one per logged-in account. The only network calls are to the
providers/trackers you've connected (GitHub, Linear, etc.), your configured AI
provider, and the billing backend for login/usage-counting described above.

See [05-security.md](05-security.md).

### Can I use this without a GitHub account?

No. GitHub OAuth is currently the only login method - there's no password/email
signup path.

### What happened to the `worker/` directory referenced in old commits/issues?

It was a Cloudflare Worker that used to front Stripe billing and a download redirect.
It was confirmed dead code (nothing in the app called its deployed URL - all billing
calls go through `AKIRA_BILLING_URL` directly) and removed from the repository in the
open-source transition.

See [07-operations.md](07-operations.md).

### Why does Autopilot not have a backend "start job" command?

Because the orchestration loop - deciding which issue runs next, calling the chat
session, watching completion - deliberately lives in the frontend
(`useAutopilotStore.ts`), not the Rust backend. The backend only persists
job/thread/log rows.

See [domains/autopilot.md](domains/autopilot.md).

### How do I add support for a new git host or issue tracker?

For a git host: implement the `VcsProvider` trait and register a
`ProviderDriverFactory` in `src-tauri/src/providers/registry.rs`. For an issue
tracker: add a case to `TrackerRegistry::build` in
`src-tauri/src/tracker/registry.rs`, backed by the external `omnitrack` crate.

See [domains/providers.md](domains/providers.md) and [domains/tracker.md](domains/tracker.md).

### Why is the CI release workflow still using pnpm when the project uses Bun?

It's a known inconsistency - the workflow wasn't updated when the project
standardized on Bun.

See [07-operations.md](07-operations.md).
