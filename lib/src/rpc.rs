use serde::{Deserialize, Serialize};

pub use crate::models::{
  ImportEnvironmentPreview, ImportEnvironmentResolution, ImportPreview,
  ImportResolution, ImportResult, ImportVaultPreview, ImportVaultResolution,
};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VaultInfo {
  pub id: String,
  pub name: String,
  pub description: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ListSecretsRequest {
  pub vault_id: String,
  pub environment: String,
  pub master_password: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SecretEntry {
  pub key: String,
  pub value: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EnvironmentInfo {
  pub id: String,
  pub name: String,
  pub display_order: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EncryptedSecretEntry {
  pub encrypted_key: Vec<u8>,
  pub key_nonce: Vec<u8>,
  pub encrypted_value: Vec<u8>,
  pub value_nonce: Vec<u8>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ApiKeyLoadResponse {
  pub api_key_id: String,
  pub vault_id: String,
  pub environment: String,
  pub name: String,
  pub secrets: Vec<EncryptedSecretEntry>,
}

#[tarpc::service]
pub trait Vault0Service {
  async fn list_vaults() -> Result<Vec<VaultInfo>, String>;

  async fn list_environments(
    vault_id: String,
  ) -> Result<Vec<EnvironmentInfo>, String>;

  async fn list_secrets(
    request: ListSecretsRequest,
  ) -> Result<Vec<SecretEntry>, String>;

  async fn create_secret(
    vault_id: String,
    environment: String,
    key: String,
    value: String,
  ) -> Result<(), String>;

  async fn load_with_api_key(
    api_key: String,
  ) -> Result<ApiKeyLoadResponse, String>;

  async fn export_vaults(
    vault_ids: Vec<String>,
    master_password: String,
    export_password: String,
  ) -> Result<String, String>;

  async fn preview_import(
    envelope: String,
    export_password: String,
  ) -> Result<ImportPreview, String>;

  async fn import_vaults(
    envelope: String,
    export_password: String,
    resolution: ImportResolution,
  ) -> Result<ImportResult, String>;
}
