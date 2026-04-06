CREATE TABLE IF NOT EXISTS mcp_servers (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    url TEXT NOT NULL,
    access_token TEXT,
    token_type TEXT NOT NULL DEFAULT 'bearer',
    enabled INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL
);
