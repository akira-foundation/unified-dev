ALTER TABLE github_contribution_profiles ADD COLUMN customer_id TEXT;
CREATE INDEX IF NOT EXISTS idx_github_contribution_profiles_customer_id ON github_contribution_profiles(customer_id);
UPDATE github_contribution_profiles SET customer_id = (SELECT customer_id FROM license WHERE id = 'local') WHERE customer_id IS NULL;
