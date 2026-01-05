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
