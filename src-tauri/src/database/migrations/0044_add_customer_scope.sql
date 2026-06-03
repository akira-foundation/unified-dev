ALTER TABLE providers ADD COLUMN customer_id TEXT;
ALTER TABLE projects ADD COLUMN customer_id TEXT;
ALTER TABLE tracker_credentials ADD COLUMN customer_id TEXT;

CREATE INDEX IF NOT EXISTS idx_providers_customer_id ON providers(customer_id);
CREATE INDEX IF NOT EXISTS idx_projects_customer_id ON projects(customer_id);
CREATE INDEX IF NOT EXISTS idx_tracker_credentials_customer_id ON tracker_credentials(customer_id);
