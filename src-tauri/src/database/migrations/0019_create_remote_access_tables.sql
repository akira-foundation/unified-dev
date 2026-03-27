CREATE TABLE IF NOT EXISTS remote_settings (
  id TEXT PRIMARY KEY,
  enabled INTEGER NOT NULL DEFAULT 0,
  host_name TEXT NOT NULL,
  host_fingerprint TEXT NOT NULL,
  bind_address TEXT NOT NULL DEFAULT '127.0.0.1',
  port INTEGER NOT NULL DEFAULT 4280,
  tailscale_required INTEGER NOT NULL DEFAULT 1,
  pairing_code TEXT NOT NULL,
  pairing_code_expires_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS remote_devices (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  token_hash TEXT,
  fingerprint TEXT,
  user_agent TEXT,
  last_seen_at TEXT,
  revoked_at TEXT,
  created_at TEXT NOT NULL
);
