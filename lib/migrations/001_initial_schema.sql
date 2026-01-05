CREATE TABLE IF NOT EXISTS master_passwords (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    password_hash TEXT NOT NULL,
    secret_code_salt BLOB NOT NULL,
    master_key_salt BLOB NOT NULL,
    ecdsa_public_key BLOB,
    argon2_params TEXT NOT NULL DEFAULT '{"m":131072,"t":4,"p":4}',
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS app_settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS vaults (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    description TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS vault_encryption_keys (
    vault_id TEXT PRIMARY KEY,
    encrypted_key BLOB NOT NULL,
    nonce BLOB NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    FOREIGN KEY (vault_id) REFERENCES vaults(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_vault_keys ON vault_encryption_keys(vault_id);

CREATE TABLE IF NOT EXISTS vault_environments (
    id TEXT PRIMARY KEY,
    vault_id TEXT NOT NULL,
    name TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    display_order INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY (vault_id) REFERENCES vaults(id) ON DELETE CASCADE,
    UNIQUE(vault_id, name)
);

CREATE INDEX IF NOT EXISTS idx_vault_environments_vault ON vault_environments(vault_id);

CREATE TABLE IF NOT EXISTS secrets (
    id TEXT PRIMARY KEY,
    vault_id TEXT NOT NULL,
    environment TEXT NOT NULL,
    encrypted_key BLOB NOT NULL,
    encrypted_value BLOB NOT NULL,
    key_nonce BLOB NOT NULL,
    value_nonce BLOB NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    FOREIGN KEY (vault_id) REFERENCES vaults(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_secrets_vault_env ON secrets(vault_id, environment);

CREATE TABLE IF NOT EXISTS api_keys (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    vault_id TEXT NOT NULL,
    environment TEXT NOT NULL,
    encrypted_dek BLOB NOT NULL,
    dek_nonce BLOB NOT NULL,
    expires_at INTEGER,
    created_at INTEGER NOT NULL,
    last_used_at INTEGER,
    FOREIGN KEY (vault_id) REFERENCES vaults(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_api_keys_vault_env ON api_keys(vault_id, environment);
CREATE INDEX IF NOT EXISTS idx_api_keys_expires ON api_keys(expires_at);

CREATE TABLE IF NOT EXISTS api_key_secrets (
    id TEXT PRIMARY KEY,
    api_key_id TEXT NOT NULL,
    secret_id TEXT NOT NULL,
    encrypted_key BLOB NOT NULL,
    encrypted_value BLOB NOT NULL,
    key_nonce BLOB NOT NULL,
    value_nonce BLOB NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    FOREIGN KEY (api_key_id) REFERENCES api_keys(id) ON DELETE CASCADE,
    FOREIGN KEY (secret_id) REFERENCES secrets(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_api_key_secrets_api_key ON api_key_secrets(api_key_id);
CREATE INDEX IF NOT EXISTS idx_api_key_secrets_secret ON api_key_secrets(secret_id);

INSERT OR IGNORE INTO app_settings (key, value, updated_at)
VALUES
    ('onboarding_completed', 'false', strftime('%s', 'now')),
    ('encryption_version', '1', strftime('%s', 'now'));

INSERT OR IGNORE INTO vaults (id, name, description, created_at, updated_at)
VALUES
    (lower(hex(randomblob(16))), 'default', 'Your default vault for storing secrets', strftime('%s', 'now'), strftime('%s', 'now'));

INSERT OR IGNORE INTO vault_environments (id, vault_id, name, created_at, display_order)
VALUES
    (lower(hex(randomblob(16))), (SELECT id FROM vaults WHERE name = 'default'), 'development', strftime('%s', 'now'), 0),
    (lower(hex(randomblob(16))), (SELECT id FROM vaults WHERE name = 'default'), 'production', strftime('%s', 'now'), 1);
