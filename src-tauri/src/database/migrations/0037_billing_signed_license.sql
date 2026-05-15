ALTER TABLE license ADD COLUMN license_key_id TEXT;
ALTER TABLE license ADD COLUMN license_algorithm TEXT;
ALTER TABLE license ADD COLUMN license_payload TEXT;
ALTER TABLE license ADD COLUMN license_signature TEXT;
ALTER TABLE license ADD COLUMN features_json TEXT;
ALTER TABLE license ADD COLUMN device_id TEXT;
