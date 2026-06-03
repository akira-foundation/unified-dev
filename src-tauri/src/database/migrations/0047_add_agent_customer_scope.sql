ALTER TABLE local_repositories ADD COLUMN customer_id TEXT;
CREATE INDEX IF NOT EXISTS idx_local_repositories_customer_id ON local_repositories(customer_id);

CREATE TABLE skills_scoped (
    id TEXT NOT NULL,
    name TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    enabled INTEGER NOT NULL DEFAULT 1,
    icon_path TEXT,
    installed_at TEXT NOT NULL,
    source_path TEXT NOT NULL,
    scope TEXT NOT NULL DEFAULT 'global',
    customer_id TEXT,
    PRIMARY KEY (id, customer_id)
);
INSERT INTO skills_scoped (id, name, description, enabled, icon_path, installed_at, source_path, scope, customer_id)
SELECT id, name, description, enabled, icon_path, installed_at, source_path, scope,
       (SELECT customer_id FROM license WHERE id = 'local')
FROM skills;
DROP TABLE skills;
ALTER TABLE skills_scoped RENAME TO skills;
CREATE INDEX IF NOT EXISTS idx_skills_customer_id ON skills(customer_id);

CREATE TABLE mcp_servers_scoped (
    id TEXT NOT NULL,
    name TEXT NOT NULL,
    url TEXT NOT NULL,
    access_token TEXT,
    token_type TEXT NOT NULL DEFAULT 'bearer',
    enabled INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL,
    customer_id TEXT,
    PRIMARY KEY (id, customer_id)
);
INSERT INTO mcp_servers_scoped (id, name, url, access_token, token_type, enabled, created_at, customer_id)
SELECT id, name, url, access_token, token_type, enabled, created_at,
       (SELECT customer_id FROM license WHERE id = 'local')
FROM mcp_servers;
DROP TABLE mcp_servers;
ALTER TABLE mcp_servers_scoped RENAME TO mcp_servers;
CREATE INDEX IF NOT EXISTS idx_mcp_servers_customer_id ON mcp_servers(customer_id);
