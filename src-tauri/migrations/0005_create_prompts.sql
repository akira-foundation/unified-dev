CREATE TABLE IF NOT EXISTS prompts (
  action     TEXT PRIMARY KEY,
  content    TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
