PRAGMA foreign_keys = OFF;

CREATE TABLE organizations_new (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  provider_id TEXT,
  external_id TEXT,
  created_at TEXT NOT NULL,
  FOREIGN KEY (provider_id) REFERENCES providers(id) ON DELETE SET NULL
);

INSERT INTO organizations_new (id, name, provider_id, external_id, created_at)
SELECT id, name, provider_id, external_id, created_at FROM organizations;

DROP TABLE organizations;

ALTER TABLE organizations_new RENAME TO organizations;

CREATE INDEX IF NOT EXISTS idx_organization_repos_org_id ON organization_repos(organization_id);
CREATE INDEX IF NOT EXISTS idx_repos_org_id ON repos(organization_id);

PRAGMA foreign_keys = ON;
