use anyhow::{bail, Result};
use diesel::prelude::*;
use diesel::sql_query;
use diesel::sql_types::{BigInt, Text};
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
