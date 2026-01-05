use anyhow::{bail, Result};
use diesel::prelude::*;
use diesel::sql_query;
use diesel::sql_types::{BigInt, Binary, Text};
use uuid::Uuid;

use crate::crypto;
use crate::models::SecretResponse;
use crate::session;

#[derive(QueryableByName)]
struct SecretRow {
  #[diesel(sql_type = Text)]
  id: String,
  #[diesel(sql_type = Text)]
  vault_id: String,
  #[diesel(sql_type = Text)]
  environment: String,
  #[diesel(sql_type = Binary)]
  encrypted_key: Vec<u8>,
  #[diesel(sql_type = Binary)]
  encrypted_value: Vec<u8>,
  #[diesel(sql_type = Binary)]
  key_nonce: Vec<u8>,
  #[diesel(sql_type = Binary)]
  value_nonce: Vec<u8>,
  #[diesel(sql_type = BigInt)]
  created_at: i64,
  #[diesel(sql_type = BigInt)]
  updated_at: i64,
}

#[derive(QueryableByName)]
struct SecretKeyRow {
  #[diesel(sql_type = Binary)]
  encrypted_key: Vec<u8>,
  #[diesel(sql_type = Binary)]
  key_nonce: Vec<u8>,
}

#[derive(QueryableByName)]
struct SecretDataRow {
  #[diesel(sql_type = Text)]
  vault_id: String,
  #[diesel(sql_type = Text)]
  environment: String,
}

pub fn list(
  vault_id: &str,
  environment: Option<&str>,
) -> Result<Vec<SecretResponse>> {
  let mut conn = super::conn()?;
  let vault_key = session::get_vault_key(vault_id)?;

  let rows: Vec<SecretRow> = if let Some(env) = environment {
    sql_query(
      "SELECT id, vault_id, environment, encrypted_key, encrypted_value, key_nonce, value_nonce, created_at, updated_at
       FROM secrets WHERE vault_id = ? AND environment = ?",
    )
    .bind::<Text, _>(vault_id)
    .bind::<Text, _>(env)
    .load(&mut conn)?
  } else {
    sql_query(
      "SELECT id, vault_id, environment, encrypted_key, encrypted_value, key_nonce, value_nonce, created_at, updated_at
       FROM secrets WHERE vault_id = ?",
    )
    .bind::<Text, _>(vault_id)
    .load(&mut conn)?
  };

  let mut secrets = Vec::new();

  for row in rows {
    let key_nonce_array: [u8; 12] = row
      .key_nonce
      .try_into()
      .map_err(|_| anyhow::anyhow!("Invalid key nonce"))?;
    let value_nonce_array: [u8; 12] = row
      .value_nonce
      .try_into()
      .map_err(|_| anyhow::anyhow!("Invalid value nonce"))?;

    let key_plaintext = crypto::decrypt_data(
      vault_key.as_bytes(),
      &crypto::EncryptedData {
        ciphertext: row.encrypted_key,
        nonce: key_nonce_array,
      },
    )?;

    let value_plaintext = crypto::decrypt_data(
      vault_key.as_bytes(),
      &crypto::EncryptedData {
        ciphertext: row.encrypted_value,
        nonce: value_nonce_array,
      },
    )?;

    secrets.push(SecretResponse {
      id: row.id,
      vault_id: row.vault_id,
      environment: row.environment,
      key: String::from_utf8(key_plaintext)?,
      value: String::from_utf8(value_plaintext)?,
      created_at: row.created_at,
      updated_at: row.updated_at,
    });
  }

  Ok(secrets)
}

fn secret_exists(
  conn: &mut SqliteConnection,
  vault_id: &str,
  environment: &str,
  key: &str,
  vault_key: &crypto::VaultKey,
) -> Result<bool> {
  let rows: Vec<SecretKeyRow> = sql_query(
    "SELECT encrypted_key, key_nonce FROM secrets WHERE vault_id = ? AND environment = ?",
  )
  .bind::<Text, _>(vault_id)
  .bind::<Text, _>(environment)
  .load(conn)?;

  for row in rows {
    let key_nonce_array: [u8; 12] = row
      .key_nonce
      .try_into()
      .map_err(|_| anyhow::anyhow!("Invalid nonce"))?;

    let decrypted_key = crypto::decrypt_data(
      vault_key.as_bytes(),
      &crypto::EncryptedData {
        ciphertext: row.encrypted_key,
        nonce: key_nonce_array,
      },
    )?;

    if String::from_utf8(decrypted_key)? == key {
      return Ok(true);
    }
  }

  Ok(false)
}

pub fn create(
  vault_id: &str,
  environment: &str,
  key: &str,
  value: &str,
) -> Result<()> {
  if environment.contains(' ') || key.contains(' ') {
    bail!("Environment and key cannot contain spaces");
  }

  let mut conn = super::conn()?;
  let vault_key = session::get_vault_key(vault_id)?;

  if secret_exists(&mut conn, vault_id, environment, key, &vault_key)? {
    bail!("Secret '{}' already exists", key);
  }

  let encrypted_key =
    crypto::encrypt_data(vault_key.as_bytes(), key.as_bytes())?;
  let encrypted_value =
    crypto::encrypt_data(vault_key.as_bytes(), value.as_bytes())?;

  let now = chrono::Utc::now().timestamp();
  let id = Uuid::new_v4().to_string();

  sql_query(
    "INSERT OR REPLACE INTO secrets (id, vault_id, environment, encrypted_key, encrypted_value, key_nonce, value_nonce, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
  )
  .bind::<Text, _>(&id)
  .bind::<Text, _>(vault_id)
  .bind::<Text, _>(environment)
  .bind::<Binary, _>(&encrypted_key.ciphertext)
  .bind::<Binary, _>(&encrypted_value.ciphertext)
  .bind::<Binary, _>(encrypted_key.nonce.as_slice())
  .bind::<Binary, _>(encrypted_value.nonce.as_slice())
  .bind::<BigInt, _>(now)
  .bind::<BigInt, _>(now)
  .execute(&mut conn)?;

  let _ = super::api_key::sync_secret(
    &id,
    vault_id,
    environment,
    &encrypted_key.ciphertext,
    &encrypted_key.nonce,
    &encrypted_value.ciphertext,
    &encrypted_value.nonce,
  );

  Ok(())
}

pub fn update(id: &str, value: &str) -> Result<()> {
  let mut conn = super::conn()?;

  let rows: Vec<SecretDataRow> =
    sql_query("SELECT vault_id, environment FROM secrets WHERE id = ?")
      .bind::<Text, _>(id)
      .load(&mut conn)?;

  let row = rows
    .first()
    .ok_or_else(|| anyhow::anyhow!("Secret not found"))?;

  let vault_id = row.vault_id.clone();
  let environment = row.environment.clone();

  let vault_key = session::get_vault_key(&vault_id)?;
  let encrypted_value =
    crypto::encrypt_data(vault_key.as_bytes(), value.as_bytes())?;
  let now = chrono::Utc::now().timestamp();

  sql_query("UPDATE secrets SET encrypted_value = ?, value_nonce = ?, updated_at = ? WHERE id = ?")
    .bind::<Binary, _>(&encrypted_value.ciphertext)
    .bind::<Binary, _>(encrypted_value.nonce.as_slice())
    .bind::<BigInt, _>(now)
    .bind::<Text, _>(id)
    .execute(&mut conn)?;

  let rows: Vec<SecretKeyRow> =
    sql_query("SELECT encrypted_key, key_nonce FROM secrets WHERE id = ?")
      .bind::<Text, _>(id)
      .load(&mut conn)?;

  let row = rows
    .first()
    .ok_or_else(|| anyhow::anyhow!("Secret not found"))?;

  let key_nonce_array: [u8; 12] = row
    .key_nonce
    .clone()
    .try_into()
    .map_err(|_| anyhow::anyhow!("Invalid nonce"))?;

  let _ = super::api_key::sync_secret(
    id,
    &vault_id,
    &environment,
    &row.encrypted_key,
    &key_nonce_array,
    &encrypted_value.ciphertext,
    &encrypted_value.nonce,
  );

  Ok(())
}

pub fn delete(id: &str) -> Result<()> {
  let mut conn = super::conn()?;

  sql_query("DELETE FROM secrets WHERE id = ?")
    .bind::<Text, _>(id)
    .execute(&mut conn)?;

  let _ = super::api_key::delete_for_secret(id);
  Ok(())
}
