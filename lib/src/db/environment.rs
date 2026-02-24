use anyhow::{bail, Result};
use diesel::prelude::*;
use diesel::sql_query;
use diesel::sql_types::{BigInt, Binary, Text};
use uuid::Uuid;

use crate::models::EnvironmentResponse;

#[derive(QueryableByName)]
struct EnvironmentRow {
  #[diesel(sql_type = Text)]
  id: String,
  #[diesel(sql_type = Text)]
  name: String,
  #[diesel(sql_type = BigInt)]
  created_at: i64,
  #[diesel(sql_type = BigInt)]
  display_order: i64,
}

#[derive(QueryableByName)]
struct CountRow {
  #[diesel(sql_type = BigInt)]
  count: i64,
}

#[derive(QueryableByName)]
struct MaxOrderRow {
  #[diesel(sql_type = BigInt)]
  max_order: i64,
}

pub fn list(vault_id: &str) -> Result<Vec<EnvironmentResponse>> {
  let mut conn = super::conn()?;

  let rows: Vec<EnvironmentRow> = sql_query(
    "SELECT id, name, created_at, display_order FROM vault_environments WHERE vault_id = ? ORDER BY display_order",
  )
  .bind::<Text, _>(vault_id)
  .load(&mut conn)?;

  Ok(
    rows
      .into_iter()
      .map(|r| EnvironmentResponse {
        id: r.id,
        name: r.name,
        created_at: r.created_at,
        display_order: r.display_order,
      })
      .collect(),
  )
}

pub fn create(vault_id: &str, name: &str) -> Result<()> {
  let mut conn = super::conn()?;
  let name_lower = name.trim().to_lowercase();

  if name_lower.contains(' ') {
    bail!("Environment name cannot contain spaces");
  }

  let now = chrono::Utc::now().timestamp();

  let rows: Vec<MaxOrderRow> = sql_query(
    "SELECT IFNULL(MAX(display_order), -1) as max_order FROM vault_environments WHERE vault_id = ?",
  )
  .bind::<Text, _>(vault_id)
  .load(&mut conn)?;

  let max_order = rows.first().map(|r| r.max_order).unwrap_or(-1);
  let id = Uuid::new_v4().to_string();

  sql_query(
    "INSERT INTO vault_environments (id, vault_id, name, created_at, display_order) VALUES (?, ?, ?, ?, ?)",
  )
  .bind::<Text, _>(&id)
  .bind::<Text, _>(vault_id)
  .bind::<Text, _>(&name_lower)
  .bind::<BigInt, _>(now)
  .bind::<BigInt, _>(max_order + 1)
  .execute(&mut conn)?;

  Ok(())
}

pub fn clone(vault_id: &str, source_name: &str, new_name: &str) -> Result<()> {
  create(vault_id, new_name)?;

  #[derive(QueryableByName)]
  struct SecretCopyRow {
    #[diesel(sql_type = Binary)]
    encrypted_key: Vec<u8>,
    #[diesel(sql_type = Binary)]
    encrypted_value: Vec<u8>,
    #[diesel(sql_type = Binary)]
    key_nonce: Vec<u8>,
    #[diesel(sql_type = Binary)]
    value_nonce: Vec<u8>,
  }

  let mut conn = super::conn()?;

  let rows: Vec<SecretCopyRow> = sql_query(
    "SELECT encrypted_key, encrypted_value, key_nonce, value_nonce FROM secrets WHERE vault_id = ? AND environment = ?",
  )
  .bind::<Text, _>(vault_id)
  .bind::<Text, _>(source_name)
  .load(&mut conn)?;

  let now = chrono::Utc::now().timestamp();

  for row in rows {
    let key_nonce_array: [u8; 12] = row
      .key_nonce
      .as_slice()
      .try_into()
      .map_err(|_| anyhow::anyhow!("Invalid key nonce"))?;
    let value_nonce_array: [u8; 12] = row
      .value_nonce
      .as_slice()
      .try_into()
      .map_err(|_| anyhow::anyhow!("Invalid value nonce"))?;

    let id = Uuid::new_v4().to_string();

    sql_query(
      "INSERT INTO secrets (id, vault_id, environment, encrypted_key, encrypted_value, key_nonce, value_nonce, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
    )
    .bind::<Text, _>(&id)
    .bind::<Text, _>(vault_id)
    .bind::<Text, _>(new_name)
    .bind::<Binary, _>(&row.encrypted_key)
    .bind::<Binary, _>(&row.encrypted_value)
    .bind::<Binary, _>(key_nonce_array.as_slice())
    .bind::<Binary, _>(value_nonce_array.as_slice())
    .bind::<BigInt, _>(now)
    .bind::<BigInt, _>(now)
    .execute(&mut conn)?;

    let _ = super::api_key::sync_secret(
      &id,
      vault_id,
      new_name,
      &row.encrypted_key,
      &key_nonce_array,
      &row.encrypted_value,
      &value_nonce_array,
    );
  }

  Ok(())
}

pub fn delete(vault_id: &str, name: &str) -> Result<()> {
  let mut conn = super::conn()?;

  let rows: Vec<CountRow> = sql_query(
    "SELECT COUNT(*) as count FROM vault_environments WHERE vault_id = ?",
  )
  .bind::<Text, _>(vault_id)
  .load(&mut conn)?;

  let count = rows.first().map(|r| r.count).unwrap_or(0);

  if count <= 1 {
    bail!("Cannot delete the last environment");
  }

  sql_query(
    "DELETE FROM api_key_secrets WHERE secret_id IN (SELECT id FROM secrets WHERE vault_id = ? AND environment = ?)",
  )
  .bind::<Text, _>(vault_id)
  .bind::<Text, _>(name)
  .execute(&mut conn)?;

  sql_query("DELETE FROM api_keys WHERE vault_id = ? AND environment = ?")
    .bind::<Text, _>(vault_id)
    .bind::<Text, _>(name)
    .execute(&mut conn)?;

  sql_query("DELETE FROM secrets WHERE vault_id = ? AND environment = ?")
    .bind::<Text, _>(vault_id)
    .bind::<Text, _>(name)
    .execute(&mut conn)?;

  sql_query("DELETE FROM vault_environments WHERE vault_id = ? AND name = ?")
    .bind::<Text, _>(vault_id)
    .bind::<Text, _>(name)
    .execute(&mut conn)?;

  Ok(())
}
