ALTER TABLE local_repositories ADD COLUMN customer_id TEXT;
ALTER TABLE skills ADD COLUMN customer_id TEXT;
ALTER TABLE mcp_servers ADD COLUMN customer_id TEXT;

CREATE INDEX IF NOT EXISTS idx_local_repositories_customer_id ON local_repositories(customer_id);
CREATE INDEX IF NOT EXISTS idx_skills_customer_id ON skills(customer_id);
CREATE INDEX IF NOT EXISTS idx_mcp_servers_customer_id ON mcp_servers(customer_id);
