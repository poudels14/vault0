use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize)]
pub struct SecretResponse {
  pub id: String,
  pub vault_id: String,
  pub environment: String,
  pub key: String,
  pub value: String,
  pub created_at: i64,
  pub updated_at: i64,
  // True when this secret is inherited from a parent environment rather than
  // defined in the environment that was queried. Only set by resolved listings.
  #[serde(default)]
  pub inherited: bool,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct VaultResponse {
  pub id: String,
  pub name: String,
  pub description: Option<String>,
  pub created_at: i64,
  pub updated_at: i64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct EnvironmentResponse {
  pub id: String,
  pub name: String,
  pub created_at: i64,
  pub display_order: i64,
  // id of the parent environment this one inherits from, if any.
  pub parent_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ApiKey {
  pub id: String,
  pub name: String,
  pub vault_id: String,
  pub environment: String,
  pub expires_at: Option<i64>,
  pub created_at: i64,
  pub last_used_at: Option<i64>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct CreateApiKeyRequest {
  pub name: String,
  pub vault_id: String,
  pub environment: String,
  pub expiration_days: Option<i32>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ApiKeyResponse {
  pub api_key: ApiKey,
  pub jwt_token: String,
  pub api_secret: String,
}

/// JWT used for the auth
#[derive(Debug, Serialize, Deserialize)]
pub struct ApiKeyClaims {
  pub api_key_id: String,
  pub name: String,
  pub vault_id: String,
  pub environment: String,
  pub exp: Option<i64>,
  pub iat: i64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ApiSecretPayload {
  pub api_key_id: String,
  pub dek: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ImportPreview {
  pub vaults: Vec<ImportVaultPreview>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ImportVaultPreview {
  pub name: String,
  pub exists: bool,
  pub environments: Vec<ImportEnvironmentPreview>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ImportEnvironmentPreview {
  pub name: String,
  pub exists: bool,
  pub secret_count: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ImportResolution {
  pub vaults: Vec<ImportVaultResolution>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ImportVaultResolution {
  pub source_name: String,
  pub target_name: String,
  pub merge_into_existing: bool,
  pub skip: bool,
  pub environments: Vec<ImportEnvironmentResolution>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ImportEnvironmentResolution {
  pub source_name: String,
  pub target_name: String,
  pub skip: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ImportResult {
  pub vaults: Vec<String>,
  pub imported_count: i64,
  pub skipped_count: i64,
}
