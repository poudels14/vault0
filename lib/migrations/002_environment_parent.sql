ALTER TABLE vault_environments ADD COLUMN parent_id TEXT;

CREATE INDEX IF NOT EXISTS idx_vault_environments_parent ON vault_environments(parent_id);
