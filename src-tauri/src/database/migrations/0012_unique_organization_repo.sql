-- Remove any duplicate (organization_id, repo_name) pairs, keeping the one with the lowest id
DELETE FROM organization_repos WHERE id NOT IN (
  SELECT MIN(id) FROM organization_repos GROUP BY organization_id, repo_name
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_organization_repos_unique ON organization_repos (organization_id, repo_name);
