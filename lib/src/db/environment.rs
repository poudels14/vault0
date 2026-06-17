use std::collections::HashSet;

use anyhow::{bail, Result};
use diesel::prelude::*;
use diesel::sql_query;
use diesel::sql_types::{BigInt, Binary, Nullable, Text};
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
  #[diesel(sql_type = Nullable<Text>)]
  parent_id: Option<String>,
  #[diesel(sql_type = Nullable<Text>)]
  op_vault: Option<String>,
  #[diesel(sql_type = Nullable<Text>)]
  op_item: Option<String>,
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
    "SELECT id, name, created_at, display_order, parent_id, op_vault, op_item FROM vault_environments WHERE vault_id = ? ORDER BY display_order",
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
        parent_id: r.parent_id,
        op_vault: r.op_vault,
        op_item: r.op_item,
      })
      .collect(),
  )
}

fn load_rows(
  conn: &mut SqliteConnection,
  vault_id: &str,
) -> Result<Vec<EnvironmentRow>> {
  Ok(
    sql_query(
      "SELECT id, name, created_at, display_order, parent_id, op_vault, op_item FROM vault_environments WHERE vault_id = ?",
    )
    .bind::<Text, _>(vault_id)
    .load(conn)?,
  )
}

/// Returns the inheritance chain for an environment, ordered from the root
/// ancestor down to the requested environment itself. Secrets resolve by
/// walking this chain in order, with later (more derived) environments
/// overriding earlier ones.
pub fn resolve_chain(vault_id: &str, name: &str) -> Result<Vec<String>> {
  let mut conn = super::conn()?;
  let rows = load_rows(&mut conn, vault_id)?;

  let mut chain = vec![name.to_string()];
  let mut current = name.to_string();
  let mut visited = HashSet::new();
  visited.insert(current.clone());

  loop {
    let Some(row) = rows.iter().find(|r| r.name == current) else {
      break;
    };
    let Some(parent_id) = &row.parent_id else {
      break;
    };
    let Some(parent) = rows.iter().find(|r| &r.id == parent_id) else {
      break;
    };
    if !visited.insert(parent.name.clone()) {
      bail!("Environment inheritance cycle detected");
    }
    chain.push(parent.name.clone());
    current = parent.name.clone();
  }

  chain.reverse();
  Ok(chain)
}

pub fn create(vault_id: &str, name: &str, parent: Option<&str>) -> Result<()> {
  let mut conn = super::conn()?;
  let name_lower = name.trim().to_lowercase();

  if name_lower.contains(' ') {
    bail!("Environment name cannot contain spaces");
  }

  let parent_id = match parent {
    Some(p) if !p.trim().is_empty() => Some(resolve_parent_id(
      &mut conn,
      vault_id,
      &p.trim().to_lowercase(),
    )?),
    _ => None,
  };

  let now = chrono::Utc::now().timestamp();

  let rows: Vec<MaxOrderRow> = sql_query(
    "SELECT IFNULL(MAX(display_order), -1) as max_order FROM vault_environments WHERE vault_id = ?",
  )
  .bind::<Text, _>(vault_id)
  .load(&mut conn)?;

  let max_order = rows.first().map(|r| r.max_order).unwrap_or(-1);
  let id = Uuid::new_v4().to_string();

  sql_query(
    "INSERT INTO vault_environments (id, vault_id, name, created_at, display_order, parent_id) VALUES (?, ?, ?, ?, ?, ?)",
  )
  .bind::<Text, _>(&id)
  .bind::<Text, _>(vault_id)
  .bind::<Text, _>(&name_lower)
  .bind::<BigInt, _>(now)
  .bind::<BigInt, _>(max_order + 1)
  .bind::<Nullable<Text>, _>(parent_id)
  .execute(&mut conn)?;

  Ok(())
}

fn resolve_parent_id(
  conn: &mut SqliteConnection,
  vault_id: &str,
  parent_name: &str,
) -> Result<String> {
  let rows: Vec<EnvironmentRow> = sql_query(
    "SELECT id, name, created_at, display_order, parent_id, op_vault, op_item FROM vault_environments WHERE vault_id = ? AND name = ?",
  )
  .bind::<Text, _>(vault_id)
  .bind::<Text, _>(parent_name)
  .load(conn)?;

  rows.first().map(|r| r.id.clone()).ok_or_else(|| {
    anyhow::anyhow!("Parent environment '{}' not found", parent_name)
  })
}

/// Returns the id of an environment by name.
pub fn id_for(vault_id: &str, name: &str) -> Result<String> {
  let mut conn = super::conn()?;
  let rows: Vec<EnvironmentRow> = sql_query(
    "SELECT id, name, created_at, display_order, parent_id, op_vault, op_item FROM vault_environments WHERE vault_id = ? AND name = ?",
  )
  .bind::<Text, _>(vault_id)
  .bind::<Text, _>(name)
  .load(&mut conn)?;

  rows
    .first()
    .map(|r| r.id.clone())
    .ok_or_else(|| anyhow::anyhow!("Environment '{}' not found", name))
}

/// 1Password backing for an environment: the env's secrets live in this
/// 1Password vault/item and are read/written via the `op` CLI.
pub struct OpEnvConfig {
  pub env_id: String,
  pub op_vault: String,
  pub op_item: String,
}

fn op_config_from_row(row: EnvironmentRow) -> Option<OpEnvConfig> {
  match (row.op_vault, row.op_item) {
    (Some(op_vault), Some(op_item)) => Some(OpEnvConfig {
      env_id: row.id,
      op_vault,
      op_item,
    }),
    _ => None,
  }
}

/// Returns the 1Password config for an environment by name, or None when the
/// environment stores its secrets locally.
pub fn op_config(vault_id: &str, name: &str) -> Result<Option<OpEnvConfig>> {
  let mut conn = super::conn()?;
  let rows: Vec<EnvironmentRow> = sql_query(
    "SELECT id, name, created_at, display_order, parent_id, op_vault, op_item FROM vault_environments WHERE vault_id = ? AND name = ?",
  )
  .bind::<Text, _>(vault_id)
  .bind::<Text, _>(name)
  .load(&mut conn)?;

  Ok(rows.into_iter().next().and_then(op_config_from_row))
}

/// Same as `op_config` but looked up by environment id (used to route updates
/// of op-backed secrets whose synthetic id encodes the env id).
pub fn op_config_by_id(env_id: &str) -> Result<Option<OpEnvConfig>> {
  let mut conn = super::conn()?;
  let rows: Vec<EnvironmentRow> = sql_query(
    "SELECT id, name, created_at, display_order, parent_id, op_vault, op_item FROM vault_environments WHERE id = ?",
  )
  .bind::<Text, _>(env_id)
  .load(&mut conn)?;

  Ok(rows.into_iter().next().and_then(op_config_from_row))
}

/// Stores the 1Password vault/item on an environment, marking it op-backed.
pub fn set_op_config(
  vault_id: &str,
  name: &str,
  op_vault: &str,
  op_item: &str,
) -> Result<()> {
  let mut conn = super::conn()?;
  let updated = sql_query(
    "UPDATE vault_environments SET op_vault = ?, op_item = ? WHERE vault_id = ? AND name = ?",
  )
  .bind::<Text, _>(op_vault)
  .bind::<Text, _>(op_item)
  .bind::<Text, _>(vault_id)
  .bind::<Text, _>(name)
  .execute(&mut conn)?;

  if updated == 0 {
    bail!("Environment '{}' not found", name);
  }
  Ok(())
}

/// Clears the 1Password backing, reverting the environment to local storage.
pub fn clear_op_config(vault_id: &str, name: &str) -> Result<()> {
  let mut conn = super::conn()?;
  sql_query(
    "UPDATE vault_environments SET op_vault = NULL, op_item = NULL WHERE vault_id = ? AND name = ?",
  )
  .bind::<Text, _>(vault_id)
  .bind::<Text, _>(name)
  .execute(&mut conn)?;
  Ok(())
}

/// Sets (or clears, when `parent` is None) the parent of an environment.
/// Rejects assignments that would create a cycle.
pub fn set_parent(
  vault_id: &str,
  name: &str,
  parent: Option<&str>,
) -> Result<()> {
  let name_lower = name.trim().to_lowercase();

  let parent_id = match parent {
    Some(p) if !p.trim().is_empty() => {
      let parent_lower = p.trim().to_lowercase();
      if parent_lower == name_lower {
        bail!("An environment cannot inherit from itself");
      }
      // The new parent's chain must not already include this environment,
      // otherwise we would form a cycle.
      if resolve_chain(vault_id, &parent_lower)?.contains(&name_lower) {
        bail!("This parent would create an inheritance cycle");
      }
      let mut conn = super::conn()?;
      Some(resolve_parent_id(&mut conn, vault_id, &parent_lower)?)
    }
    _ => None,
  };

  let mut conn = super::conn()?;
  let updated =
    sql_query("UPDATE vault_environments SET parent_id = ? WHERE vault_id = ? AND name = ?")
      .bind::<Nullable<Text>, _>(parent_id)
      .bind::<Text, _>(vault_id)
      .bind::<Text, _>(&name_lower)
      .execute(&mut conn)?;

  if updated == 0 {
    bail!("Environment '{}' not found", name_lower);
  }

  Ok(())
}

pub fn clone(vault_id: &str, source_name: &str, new_name: &str) -> Result<()> {
  create(vault_id, new_name, None)?;

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

  let child_rows: Vec<CountRow> = sql_query(
    "SELECT COUNT(*) as count FROM vault_environments
     WHERE vault_id = ? AND parent_id = (
       SELECT id FROM vault_environments WHERE vault_id = ? AND name = ?
     )",
  )
  .bind::<Text, _>(vault_id)
  .bind::<Text, _>(vault_id)
  .bind::<Text, _>(name)
  .load(&mut conn)?;

  if child_rows.first().map(|r| r.count).unwrap_or(0) > 0 {
    bail!("Cannot delete an environment that has child environments. Reassign or delete its children first.");
  }

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

#[cfg(test)]
mod tests {
  use super::*;
  use std::path::PathBuf;

  // Creates an isolated vault and returns its id. Avoids colliding with the
  // seeded "default" vault or other tests sharing the in-memory pool.
  fn fresh_vault(tag: &str) -> String {
    super::super::init(&PathBuf::from(":memory:")).unwrap();
    let mut conn = super::super::conn().unwrap();
    let id = Uuid::new_v4().to_string();
    let name = format!("vault-{}-{}", tag, &id[..8]);
    let now = chrono::Utc::now().timestamp();
    sql_query(
      "INSERT INTO vaults (id, name, description, created_at, updated_at) VALUES (?, ?, NULL, ?, ?)",
    )
    .bind::<Text, _>(&id)
    .bind::<Text, _>(&name)
    .bind::<BigInt, _>(now)
    .bind::<BigInt, _>(now)
    .execute(&mut conn)
    .unwrap();
    id
  }

  #[test]
  fn test_resolve_chain() {
    let _g = super::super::test_guard();
    let vault_id = fresh_vault("chain");

    create(&vault_id, "base", None).unwrap();
    create(&vault_id, "staging", Some("base")).unwrap();
    create(&vault_id, "feature", Some("staging")).unwrap();
    create(&vault_id, "prod", Some("base")).unwrap();

    assert_eq!(resolve_chain(&vault_id, "base").unwrap(), vec!["base"]);
    assert_eq!(
      resolve_chain(&vault_id, "feature").unwrap(),
      vec!["base", "staging", "feature"]
    );
    assert_eq!(
      resolve_chain(&vault_id, "prod").unwrap(),
      vec!["base", "prod"]
    );
  }

  #[test]
  fn test_set_parent_rejects_cycle() {
    let _g = super::super::test_guard();
    let vault_id = fresh_vault("cycle");

    create(&vault_id, "a", None).unwrap();
    create(&vault_id, "b", Some("a")).unwrap();
    create(&vault_id, "c", Some("b")).unwrap();

    // Making "a" inherit from its own descendant "c" must be rejected.
    assert!(set_parent(&vault_id, "a", Some("c")).is_err());
    // Re-parenting within the tree without a cycle is allowed.
    assert!(set_parent(&vault_id, "c", Some("a")).is_ok());
    assert_eq!(resolve_chain(&vault_id, "c").unwrap(), vec!["a", "c"]);
  }

  #[test]
  fn test_delete_blocks_when_children_exist() {
    let _g = super::super::test_guard();
    let vault_id = fresh_vault("del");

    create(&vault_id, "parent", None).unwrap();
    create(&vault_id, "child", Some("parent")).unwrap();
    create(&vault_id, "other", None).unwrap();

    // Blocked while a child still references it.
    assert!(delete(&vault_id, "parent").is_err());
    assert!(delete(&vault_id, "child").is_ok());
    // Now that the child is gone, the parent can be deleted.
    assert!(delete(&vault_id, "parent").is_ok());
  }
}
