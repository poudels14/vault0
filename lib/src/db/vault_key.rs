use anyhow::{bail, Result};
use diesel::prelude::*;
use diesel::sql_query;
use diesel::sql_types::{BigInt, Binary, Integer, Text};

use crate::crypto::{self, EncryptedData, VaultKey};
use crate::session;

#[derive(QueryableByName)]
struct VaultKeyRow {
  #[diesel(sql_type = Binary)]
  encrypted_key: Vec<u8>,
  #[diesel(sql_type = Binary)]
  nonce: Vec<u8>,
}

#[derive(QueryableByName)]
struct ExistsRow {
  #[diesel(sql_type = Integer)]
  exists_flag: i32,
}

pub fn get_or_create(vault_id: &str) -> Result<VaultKey> {
  let master_key = session::get_master_key()?;
  let mut conn = super::conn()?;

  let rows: Vec<VaultKeyRow> = sql_query(
    "SELECT encrypted_key, nonce FROM vault_encryption_keys WHERE vault_id = ?",
  )
  .bind::<Text, _>(vault_id)
  .load(&mut conn)?;

  let vault_key = if let Some(row) = rows.first() {
    let nonce: [u8; 12] = row
      .nonce
      .clone()
      .try_into()
      .map_err(|_| anyhow::anyhow!("Invalid nonce length"))?;

    let encrypted_data = EncryptedData {
      ciphertext: row.encrypted_key.clone(),
      nonce,
    };

    let decrypted_bytes =
      crypto::decrypt_data(master_key.as_bytes(), &encrypted_data)?;

    let key_array: [u8; 32] = decrypted_bytes
      .try_into()
      .map_err(|_| anyhow::anyhow!("Decrypted vault key is not 32 bytes"))?;

    VaultKey::from_bytes(key_array)
  } else {
    let rows: Vec<ExistsRow> = sql_query(
      "SELECT EXISTS(SELECT 1 FROM vaults WHERE id = ?) as exists_flag",
    )
    .bind::<Text, _>(vault_id)
    .load(&mut conn)?;

    let vault_exists =
      rows.first().map(|r| r.exists_flag != 0).unwrap_or(false);

    if !vault_exists {
      bail!("Vault not found: {}", vault_id);
    }

    let vault_key = crypto::generate_vault_key();
    let encrypted =
      crypto::encrypt_data(master_key.as_bytes(), vault_key.as_bytes())?;

    let now = chrono::Utc::now().timestamp();
    sql_query(
      "INSERT INTO vault_encryption_keys (vault_id, encrypted_key, nonce, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
    )
    .bind::<Text, _>(vault_id)
    .bind::<Binary, _>(&encrypted.ciphertext)
    .bind::<Binary, _>(encrypted.nonce.as_slice())
    .bind::<BigInt, _>(now)
    .bind::<BigInt, _>(now)
    .execute(&mut conn)?;

    vault_key
  };

  Ok(vault_key)
}
