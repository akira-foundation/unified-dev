# Autopilot

## What it is

Autopilot queues a batch of issues for an AI agent to work through unattended - each
issue gets its own chat thread, run silently (no visible back-and-forth), and can
optionally open a PR when the agent is done.

## Where the orchestration actually lives

This is worth being explicit about: the **backend only persists state**
(`src-tauri/src/app/autopilot/operations.rs` - `save_job`, `update_job`, `save_thread`,
`update_thread`, `delete_job`, `delete_thread`, `write_log`, `list_jobs`, exposed as
`autopilot_*` Tauri commands in `commands/autopilot.rs`). There is no backend "start" or
"stop" command. The actual job loop - deciding which issue runs next, calling the chat
session, watching for completion, deciding whether to create a PR - is driven entirely by
the frontend, in `src/stores/useAutopilotStore.ts`.

## Data model

- `autopilot_jobs`: `id`, `repo_id`, `repo_name`, `config` (JSON - batch size, delay
 between issues, model mode, issue filter, PR mode, conflict resolution), `issues` (JSON
 array of the batch), `total`, `status` (`running`/`pending`/`completed`/`failed`),
 `started_at`, `finished_at`.
- `autopilot_threads`: one row per issue in the job - `issue_id`, `issue_number`,
 `issue_title`, `thread_id` (the chat thread once created), `status`
 (`pending`→`creating`→`streaming`→`idle`→`done`/`error`), `sort_order`.
- An audit log table records events (`thread_started`, `pr_created`, etc.) tagged with
 `job_id`, `thread_row_id`, `model_id`, `repo_name`, `issue_id`.

## End-to-end flow

1. User opens the autopilot dialog, configures batch size / delay / model / issue filter
  (all / unassigned / no PR yet / assigned to me) / PR mode (off / draft / ready) /
  conflict resolution, and starts the job.
2. Frontend calls `autopilot_save_job` to persist the job row, then `autopilot_save_thread`
  once per issue in the batch.
3. For each thread, the frontend calls into the same chat session machinery used by
  interactive chat (`app/chat/session.rs::run()`), but silent and with `plan_mode`, so the
  agent gets issue context and config instructions without a visible back-and-forth.
4. As the agent streams, the frontend calls `autopilot_update_thread`/`autopilot_update_job`
  to keep status in sync with what the UI shows (autopilot indicator, jobs panel).
5. If PR mode is enabled, the agent's tool-use includes creating a PR through the normal
  provider integration; the resulting URL is stored on the thread.
6. `autopilot_write_log` records each milestone for the job-detail timeline view.

## Constraints

- Job/thread state is DB-persisted, but the *running* loop is frontend-driven and
 in-memory - if the app is closed mid-job, the loop stops. The job row stays `"running"`
 in the DB until the app reopens and the store either resumes or the user cancels it (the
 code does not auto-resume on restart as of this writing).
- Config is a free-form JSON blob; how it's interpreted depends entirely on the system
 prompt logic in the frontend/chat layer, not on a fixed backend schema.
