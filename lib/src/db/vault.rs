use anyhow::{bail, Result};
use diesel::prelude::*;
use diesel::sql_query;
use diesel::sql_types::{BigInt, Binary, Nullable, Text};
use uuid::Uuid;

use crate::crypto;
use crate::models::VaultResponse;
use crate::session;

#[derive(QueryableByName)]
struct VaultRow {
  #[diesel(sql_type = Text)]
  id: String,
  #[diesel(sql_type = Text)]
  name: String,
  #[diesel(sql_type = Nullable<Text>)]
  description: Option<String>,
  #[diesel(sql_type = BigInt)]
  created_at: i64,
  #[diesel(sql_type = BigInt)]
  updated_at: i64,
}

pub fn create(name: &str, description: Option<&str>) -> Result<String> {
  if name.contains(' ') {
    bail!("Vault name cannot contain spaces");
  }

  let mut conn = super::conn()?;
  let now = chrono::Utc::now().timestamp();
  let id = Uuid::new_v4().to_string();

  sql_query(
    "INSERT INTO vaults (id, name, description, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
  )
  .bind::<Text, _>(&id)
  .bind::<Text, _>(name)
  .bind::<Nullable<Text>, _>(description)
  .bind::<BigInt, _>(now)
  .bind::<BigInt, _>(now)
  .execute(&mut conn)?;

  let vault_key = crypto::generate_vault_key();
  let master_key = session::get_master_key()?;
  let encrypted =
    crypto::encrypt_data(master_key.as_bytes(), vault_key.as_bytes())?;

  sql_query(
    "INSERT INTO vault_encryption_keys (vault_id, encrypted_key, nonce, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
  )
  .bind::<Text, _>(&id)
  .bind::<Binary, _>(&encrypted.ciphertext)
  .bind::<Binary, _>(encrypted.nonce.as_slice())
  .bind::<BigInt, _>(now)
  .bind::<BigInt, _>(now)
  .execute(&mut conn)?;

  Ok(id)
}

pub fn list() -> Result<Vec<VaultResponse>> {
  let mut conn = super::conn()?;

  let rows: Vec<VaultRow> =
    sql_query("SELECT id, name, description, created_at, updated_at FROM vaults ORDER BY name")
      .load(&mut conn)?;

  Ok(
    rows
      .into_iter()
      .map(|r| VaultResponse {
        id: r.id,
        name: r.name,
        description: r.description,
        created_at: r.created_at,
        updated_at: r.updated_at,
      })
      .collect(),
  )
}

pub fn update(id: &str, name: &str, description: Option<&str>) -> Result<()> {
  if name.contains(' ') {
    bail!("Vault name cannot contain spaces");
  }

  let mut conn = super::conn()?;
  let now = chrono::Utc::now().timestamp();

  sql_query(
    "UPDATE vaults SET name = ?, description = ?, updated_at = ? WHERE id = ?",
  )
  .bind::<Text, _>(name)
  .bind::<Nullable<Text>, _>(description)
  .bind::<BigInt, _>(now)
  .bind::<Text, _>(id)
  .execute(&mut conn)?;

  Ok(())
}

pub fn delete(id: &str) -> Result<()> {
  let mut conn = super::conn()?;

  sql_query("DELETE FROM vaults WHERE id = ?")
    .bind::<Text, _>(id)
    .execute(&mut conn)?;

  Ok(())
}
