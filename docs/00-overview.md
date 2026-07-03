# Project Overview

## What it is

Unified Dev is a native desktop app (Tauri, macOS today) that consolidates the surfaces a
developer normally splits across a dozen browser tabs and CLIs into one local window:
repositories, issues, pull requests, AI coding agents, and open-source contribution
insights.

## Problem it solves

Developers using AI coding agents (Claude Code, Codex, Gemini CLI, Copilot) juggle context
across GitHub/GitLab/Bitbucket, an issue tracker (Linear/Jira), and multiple terminal
sessions running agent CLIs. Unified Dev gives each of those a first-class, synced view in
one app, backed by a local database, so an agent thread has the same repo/issue context a
human would.

## Target users

Individual developers and small teams who use AI coding agents day-to-day and want a
single place to triage issues, review PRs, and delegate work to an agent without
context-switching.

## Key capabilities

- **Repositories** - clone, browse, and manage local and remote repos across GitHub,
 GitLab, and Bitbucket, with per-repo branch operations.
- **Issues & Pull Requests** - a Linear-style board synced from connected providers, with
 scope filters (mine / all open / all) and inline creation.
- **Issue trackers** - Linear and Jira integrate through a separate provider-neutral
 `tracker` seam (issue-centric, not code-centric - see
 [domains/tracker.md](domains/tracker.md)).
- **AI coding agents** - Claude, OpenAI/Codex, Gemini, and GitHub Copilot chat threads run
 against a repo from inside the app, with tool-use (file read/write, shell commands, MCP
 tools) and streaming.
- **Autopilot** - queue a batch of issues for an agent to work through unattended, each
 issue getting its own thread and (optionally) its own PR.
- **Skills & MCP** - install reusable agent skills (SKILL.md-based, project or global
 scope) and connect Model Context Protocol servers for additional tools.
- **Projects** - kanban-style boards that link repos, branches, and issues across
 providers into one view.
- **Remote access** - an embedded HTTP server (off by default) lets a paired phone or
 browser drive the same agent threads.
- **Open Source insights** - a dashboard of your public GitHub contribution activity
 (streaks, top language, most active repos), synced and cached locally.

## System boundaries

- **Local-first**: all app data lives in a SQLite database on the user's machine,
 encrypted per logged-in account (see [domains/auth-and-sessions.md](domains/auth-and-sessions.md)).
 Unified Dev does not run a server component for its own data.
- **External dependencies**: GitHub/GitLab/Bitbucket APIs, Linear/Jira APIs, AI provider
 APIs/CLIs (Anthropic, OpenAI, Google, Ollama, GitHub Copilot), and a small external
 billing backend (`AKIRA_BILLING_URL`) used only for GitHub OAuth token exchange and
 anonymous usage counting - it never sees code or credentials.
- **Free software**: as of v0.12.7, there is no paywall or license enforcement. Every
 feature is available to any logged-in user. GitHub OAuth is the only login method.

## Stack

- **Frontend**: React 19 + TypeScript + Vite, in `src/`.
- **Backend**: Rust + [Tauri 2](https://tauri.app), in `src-tauri/`. SQLite via `sqlx`,
 encrypted with SQLCipher.
- **Package manager**: [Bun](https://bun.sh).

See [01-architecture.md](01-architecture.md) for how these pieces communicate.
