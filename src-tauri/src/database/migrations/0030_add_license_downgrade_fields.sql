ALTER TABLE license ADD COLUMN cancel_at_period_end INTEGER NOT NULL DEFAULT 0;
ALTER TABLE license ADD COLUMN cancel_at TEXT;
ALTER TABLE license ADD COLUMN target_plan TEXT;
