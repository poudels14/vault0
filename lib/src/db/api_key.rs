use aes_gcm::aead::OsRng;
use anyhow::{bail, Context, Result};
use base64::{engine::general_purpose, Engine as _};
use chrono::Utc;
use diesel::prelude::*;
use diesel::sql_query;
use diesel::sql_types::{BigInt, Binary, Integer, Nullable, Text};
use jsonwebtoken::{decode, DecodingKey};
use jsonwebtoken::{encode, Algorithm, EncodingKey, Header, Validation};
use p256::pkcs8::{EncodePrivateKey, EncodePublicKey};
use rand::RngCore;
use uuid::Uuid;

use crate::crypto::{decrypt_data, encrypt_data, EncryptedData};
use crate::keychain;
use crate::models::{
  ApiKey, ApiKeyClaims, ApiKeyResponse, ApiSecretPayload, CreateApiKeyRequest,
};
use crate::session;

#[derive(QueryableByName)]
struct ExistsRow {
  #[diesel(sql_type = Integer)]
  exists_flag: i32,
}

#[derive(QueryableByName)]
struct PublicKeyRow {
  #[diesel(sql_type = Binary)]
  ecdsa_public_key: Vec<u8>,
}

#[derive(QueryableByName)]
struct ApiKeyRow {
  #[diesel(sql_type = Text)]
  id: String,
  #[diesel(sql_type = Text)]
  name: String,
  #[diesel(sql_type = Text)]
  vault_id: String,
  #[diesel(sql_type = Text)]
  environment: String,
  #[diesel(sql_type = Nullable<BigInt>)]
  expires_at: Option<i64>,
  #[diesel(sql_type = BigInt)]
  created_at: i64,
  #[diesel(sql_type = Nullable<BigInt>)]
  last_used_at: Option<i64>,
}

#[derive(QueryableByName)]
struct ApiKeyDekRow {
  #[diesel(sql_type = Text)]
  id: String,
  #[diesel(sql_type = Binary)]
  encrypted_dek: Vec<u8>,
  #[diesel(sql_type = Binary)]
  dek_nonce: Vec<u8>,
  #[diesel(sql_type = Nullable<BigInt>)]
  expires_at: Option<i64>,
}

#[derive(QueryableByName)]
struct ApiKeySecretRow {
  #[diesel(sql_type = Binary)]
  encrypted_key: Vec<u8>,
  #[diesel(sql_type = Binary)]
  key_nonce: Vec<u8>,
  #[diesel(sql_type = Binary)]
  encrypted_value: Vec<u8>,
  #[diesel(sql_type = Binary)]
  value_nonce: Vec<u8>,
}

pub struct EncryptedSecret {
  pub encrypted_key: Vec<u8>,
  pub key_nonce: Vec<u8>,
  pub encrypted_value: Vec<u8>,
  pub value_nonce: Vec<u8>,
}

pub fn create(request: &CreateApiKeyRequest) -> Result<ApiKeyResponse> {
  let mut conn = super::conn()?;
  let master_key = session::get_master_key()?;

  let rows: Vec<ExistsRow> = sql_query(
    "SELECT EXISTS(SELECT 1 FROM vaults WHERE id = ?) as exists_flag",
  )
  .bind::<Text, _>(&request.vault_id)
  .load(&mut conn)?;

  let vault_exists = rows.first().map(|r| r.exists_flag != 0).unwrap_or(false);

  if !vault_exists {
    bail!("Vault not found");
  }

  let api_key_id = Uuid::new_v4().to_string();
  let dek = generate_dek();
  let now = Utc::now().timestamp();

  let expires_at = request
    .expiration_days
    .map(|days| now + (days as i64 * 24 * 60 * 60));

  let encrypted_dek = encrypt_data(master_key.as_bytes(), &dek)?;

  sql_query(
    "INSERT INTO api_keys (id, name, vault_id, environment, encrypted_dek, dek_nonce, expires_at, created_at, last_used_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL)",
  )
  .bind::<Text, _>(&api_key_id)
  .bind::<Text, _>(&request.name)
  .bind::<Text, _>(&request.vault_id)
  .bind::<Text, _>(&request.environment)
  .bind::<Binary, _>(&encrypted_dek.ciphertext)
  .bind::<Binary, _>(encrypted_dek.nonce.as_slice())
  .bind::<Nullable<BigInt>, _>(expires_at)
  .bind::<BigInt, _>(now)
  .execute(&mut conn)?;

  rebuild_secrets_with_dek(
    &mut conn,
    &api_key_id,
    &request.vault_id,
    &request.environment,
    &dek,
  )?;

  let claims = ApiKeyClaims {
    api_key_id: api_key_id.clone(),
    name: request.name.clone(),
    vault_id: request.vault_id.clone(),
    environment: request.environment.clone(),
    exp: expires_at,
    iat: now,
  };

  let signing_key_pem = get_ecdsa_signing_key_pem()?;
  let jwt_token = encode(
    &Header::new(Algorithm::ES256),
    &claims,
    &EncodingKey::from_ec_pem(&signing_key_pem)?,
  )?;

  // API Secret - contains the DEK for client-side decryption
  let dek_base64 = general_purpose::STANDARD.encode(dek);
  let api_secret_payload = ApiSecretPayload {
    api_key_id: api_key_id.clone(),
    dek: dek_base64,
  };
  let api_secret = general_purpose::STANDARD
    .encode(serde_json::to_string(&api_secret_payload)?);

  Ok(ApiKeyResponse {
    api_key: ApiKey {
      id: api_key_id,
      name: request.name.clone(),
      vault_id: request.vault_id.clone(),
      environment: request.environment.clone(),
      expires_at,
      created_at: now,
      last_used_at: None,
    },
    jwt_token,
    api_secret,
  })
}

pub fn list(vault_id: Option<String>) -> Result<Vec<ApiKey>> {
  let mut conn = super::conn()?;

  let api_keys: Vec<ApiKeyRow> = if let Some(vid) = vault_id {
    sql_query(
      "SELECT id, name, vault_id, environment, expires_at, created_at, last_used_at FROM api_keys WHERE vault_id = ?",
    )
    .bind::<Text, _>(&vid)
    .load(&mut conn)?
  } else {
    sql_query(
      "SELECT id, name, vault_id, environment, expires_at, created_at, last_used_at FROM api_keys",
    )
    .load(&mut conn)?
  };

  Ok(
    api_keys
      .into_iter()
      .map(|r| ApiKey {
        id: r.id,
        name: r.name,
        vault_id: r.vault_id,
        environment: r.environment,
        expires_at: r.expires_at,
        created_at: r.created_at,
        last_used_at: r.last_used_at,
      })
      .collect(),
  )
}

pub fn delete(api_key_id: &str) -> Result<()> {
  let mut conn = super::conn()?;

  let result = sql_query("DELETE FROM api_keys WHERE id = ?")
    .bind::<Text, _>(api_key_id)
    .execute(&mut conn)?;

  if result == 0 {
    bail!("API key not found");
  }

  Ok(())
}

pub fn verify_and_decode_jwt(jwt_token: &str) -> Result<ApiKeyClaims> {
  let validation = Validation::new(Algorithm::ES256);
  let public_key_pem = get_ecdsa_public_key_pem()?;

  let token_data = decode::<ApiKeyClaims>(
    jwt_token,
    &DecodingKey::from_ec_pem(&public_key_pem)?,
    &validation,
  )?;

  if let Some(exp) = token_data.claims.exp {
    let now = Utc::now().timestamp();
    if now > exp {
      bail!("API key has expired");
    }
  }

  Ok(token_data.claims)
}

pub fn update_last_used(api_key_id: &str) -> Result<()> {
  let mut conn = super::conn()?;
  let now = Utc::now().timestamp();

  sql_query("UPDATE api_keys SET last_used_at = ? WHERE id = ?")
    .bind::<BigInt, _>(now)
    .bind::<Text, _>(api_key_id)
    .execute(&mut conn)?;

  Ok(())
}

pub fn get_encrypted_secrets(api_key_id: &str) -> Result<Vec<EncryptedSecret>> {
  let mut conn = super::conn()?;

  let secrets: Vec<ApiKeySecretRow> = sql_query(
    "SELECT encrypted_key, key_nonce, encrypted_value, value_nonce
     FROM api_key_secrets
     WHERE api_key_id = ?",
  )
  .bind::<Text, _>(api_key_id)
  .load(&mut conn)?;

  Ok(
    secrets
      .into_iter()
      .map(|s| EncryptedSecret {
        encrypted_key: s.encrypted_key,
        key_nonce: s.key_nonce,
        encrypted_value: s.encrypted_value,
        value_nonce: s.value_nonce,
      })
      .collect(),
  )
}

/// Rebuilds the cached secret snapshot for every API key whose environment is
/// `environment` or inherits from it, re-encrypting the resolved secret set
/// (including inherited values, with overrides applied) under each key's DEK.
/// Used whenever secrets or the inheritance chain change.
pub fn resync_env_and_descendants(
  vault_id: &str,
  environment: &str,
) -> Result<()> {
  let affected =
    super::environment::descendants_inclusive(vault_id, environment)?;

  let mut conn = super::conn()?;
  let master_key = session::get_master_key()?;
  let now = Utc::now().timestamp();

  for env in &affected {
    let api_keys: Vec<ApiKeyDekRow> = sql_query(
      "SELECT id, encrypted_dek, dek_nonce, expires_at
       FROM api_keys
       WHERE vault_id = ? AND environment = ?",
    )
    .bind::<Text, _>(vault_id)
    .bind::<Text, _>(env)
    .load(&mut conn)?;

    for api_key in api_keys {
      if let Some(exp) = api_key.expires_at {
        if now > exp {
          continue;
        }
      }

      let dek_nonce_array: [u8; 12] =
        api_key
          .dek_nonce
          .as_slice()
          .try_into()
          .map_err(|_| anyhow::anyhow!("Invalid DEK nonce size"))?;

      let dek = decrypt_data(
        master_key.as_bytes(),
        &EncryptedData {
          ciphertext: api_key.encrypted_dek,
          nonce: dek_nonce_array,
        },
      )?;

      let dek_array: [u8; 32] = dek
        .as_slice()
        .try_into()
        .map_err(|_| anyhow::anyhow!("Invalid DEK size"))?;

      rebuild_secrets_with_dek(
        &mut conn,
        &api_key.id,
        vault_id,
        env,
        &dek_array,
      )?;
    }
  }

  Ok(())
}

pub fn delete_for_secret(secret_id: &str) -> Result<()> {
  let mut conn = super::conn()?;
  sql_query("DELETE FROM api_key_secrets WHERE secret_id = ?")
    .bind::<Text, _>(secret_id)
    .execute(&mut conn)?;

  Ok(())
}

pub fn cleanup_expired() -> Result<usize> {
  let mut conn = super::conn()?;
  let now = Utc::now().timestamp();

  let result = sql_query(
    "DELETE FROM api_keys WHERE expires_at IS NOT NULL AND expires_at < ?",
  )
  .bind::<BigInt, _>(now)
  .execute(&mut conn)?;

  Ok(result)
}

fn generate_dek() -> [u8; 32] {
  let mut dek = [0u8; 32];
  OsRng.fill_bytes(&mut dek);
  dek
}

fn get_ecdsa_signing_key_pem() -> Result<Vec<u8>> {
  let master_key = session::get_master_key()?;

  let encrypted_ecdsa_hex = keychain::get_ecdsa_private_key()?;
  let encrypted_with_nonce = hex::decode(&encrypted_ecdsa_hex)?;

  if encrypted_with_nonce.len() <= 12 {
    bail!("Invalid encrypted ECDSA key format");
  }

  let nonce: [u8; 12] = encrypted_with_nonce[..12]
    .try_into()
    .map_err(|_| anyhow::anyhow!("Invalid nonce"))?;
  let ciphertext = encrypted_with_nonce[12..].to_vec();

  let encrypted_data = EncryptedData { ciphertext, nonce };
  let private_key_bytes =
    decrypt_data(&master_key.as_bytes(), &encrypted_data)?;

  let signing_key =
    crate::crypto::deserialize_ecdsa_private_key(&private_key_bytes)?;

  let pem_bytes = signing_key
    .to_pkcs8_der()
    .map_err(|e| anyhow::anyhow!("Failed to convert to DER: {}", e))?;

  Ok(
    format!(
      "-----BEGIN PRIVATE KEY-----\n{}\n-----END PRIVATE KEY-----",
      general_purpose::STANDARD.encode(pem_bytes.as_bytes())
    )
    .into_bytes(),
  )
}

fn get_ecdsa_public_key_pem() -> Result<Vec<u8>> {
  let mut conn = super::conn()?;

  let rows: Vec<PublicKeyRow> =
    sql_query("SELECT ecdsa_public_key FROM master_passwords WHERE id = 1")
      .load(&mut conn)?;

  let row = rows.first().context("ECDSA public key not found")?;

  let verifying_key =
    crate::crypto::deserialize_ecdsa_public_key(&row.ecdsa_public_key)?;

  let pem_bytes = verifying_key
    .to_public_key_der()
    .map_err(|e| anyhow::anyhow!("Failed to convert to DER: {}", e))?;

  Ok(
    format!(
      "-----BEGIN PUBLIC KEY-----\n{}\n-----END PUBLIC KEY-----",
      general_purpose::STANDARD.encode(pem_bytes.as_bytes())
    )
    .into_bytes(),
  )
}

/// Replaces an API key's cached secret snapshot with the resolved secret set
/// for `environment` (inherited values plus overrides), each re-encrypted under
/// the API key's `dek`.
fn rebuild_secrets_with_dek(
  conn: &mut SqliteConnection,
  api_key_id: &str,
  vault_id: &str,
  environment: &str,
  dek: &[u8; 32],
) -> Result<()> {
  sql_query("DELETE FROM api_key_secrets WHERE api_key_id = ?")
    .bind::<Text, _>(api_key_id)
    .execute(conn)?;

  let resolved = super::secret::list_resolved(vault_id, environment)?;

  for secret in resolved {
    let encrypted_key_dek = encrypt_data(dek, secret.key.as_bytes())?;
    let encrypted_value_dek = encrypt_data(dek, secret.value.as_bytes())?;

    let now = Utc::now().timestamp();
    let api_key_secret_id = Uuid::new_v4().to_string();

    sql_query(
      "INSERT INTO api_key_secrets (id, api_key_id, secret_id, encrypted_key, encrypted_value, key_nonce, value_nonce, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
    )
    .bind::<Text, _>(&api_key_secret_id)
    .bind::<Text, _>(api_key_id)
    .bind::<Text, _>(&secret.id)
    .bind::<Binary, _>(&encrypted_key_dek.ciphertext)
    .bind::<Binary, _>(&encrypted_value_dek.ciphertext)
    .bind::<Binary, _>(encrypted_key_dek.nonce.as_slice())
    .bind::<Binary, _>(encrypted_value_dek.nonce.as_slice())
    .bind::<BigInt, _>(now)
    .bind::<BigInt, _>(now)
    .execute(conn)?;
  }

  Ok(())
}
