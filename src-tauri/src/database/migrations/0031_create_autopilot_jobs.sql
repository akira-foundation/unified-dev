CREATE TABLE IF NOT EXISTS autopilot_jobs (
    id TEXT PRIMARY KEY NOT NULL,
    repo_id TEXT NOT NULL,
    repo_name TEXT NOT NULL,
    config TEXT NOT NULL,
    issues TEXT NOT NULL DEFAULT '[]',
    total INTEGER NOT NULL DEFAULT 0,
    created INTEGER NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'running',
    started_at TEXT NOT NULL,
    finished_at TEXT
);

CREATE TABLE IF NOT EXISTS autopilot_threads (
    id TEXT PRIMARY KEY NOT NULL,
    job_id TEXT NOT NULL REFERENCES autopilot_jobs(id) ON DELETE CASCADE,
    issue_id TEXT NOT NULL,
    issue_number INTEGER NOT NULL,
    issue_title TEXT NOT NULL,
    thread_id TEXT,
    status TEXT NOT NULL DEFAULT 'pending',
    sort_order INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS autopilot_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id TEXT NOT NULL REFERENCES autopilot_jobs(id) ON DELETE CASCADE,
    thread_row_id TEXT,
    event TEXT NOT NULL,
    model_id TEXT,
    repo_name TEXT NOT NULL,
    issue_id TEXT,
    issue_number INTEGER,
    detail TEXT,
    created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_autopilot_threads_job ON autopilot_threads(job_id);
CREATE INDEX IF NOT EXISTS idx_autopilot_logs_job ON autopilot_logs(job_id);
CREATE INDEX IF NOT EXISTS idx_autopilot_logs_event ON autopilot_logs(event);
CREATE INDEX IF NOT EXISTS idx_autopilot_logs_created_at ON autopilot_logs(created_at);
