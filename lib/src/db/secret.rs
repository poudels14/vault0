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

/// Synthetic id given to 1Password-backed secrets so update/delete can route
/// back to the right environment and key. Format: `op:{env_id}:{key}`. The
/// env id is a colonless UUID, so the key may itself contain ':'.
const OP_ID_PREFIX: &str = "op:";

fn op_secret_id(env_id: &str, key: &str) -> String {
  format!("{}{}:{}", OP_ID_PREFIX, env_id, key)
}

fn parse_op_secret_id(id: &str) -> Option<(String, String)> {
  let rest = id.strip_prefix(OP_ID_PREFIX)?;
  let (env_id, key) = rest.split_once(':')?;
  Some((env_id.to_string(), key.to_string()))
}

fn list_op(
  vault_id: &str,
  environment: &str,
  cfg: &super::environment::OpEnvConfig,
) -> Result<Vec<SecretResponse>> {
  let token = crate::keychain::get_op_token(&cfg.env_id)?;
  let fields = crate::op::get_fields(&token, &cfg.op_vault, &cfg.op_item)?;

  Ok(
    fields
      .into_iter()
      .map(|(key, value)| SecretResponse {
        id: op_secret_id(&cfg.env_id, &key),
        vault_id: vault_id.to_string(),
        environment: environment.to_string(),
        key,
        value,
        created_at: 0,
        updated_at: 0,
        inherited: false,
      })
      .collect(),
  )
}

pub fn list(
  vault_id: &str,
  environment: Option<&str>,
) -> Result<Vec<SecretResponse>> {
  let env = match environment {
    Some(env) => env,
    None => {
      // Aggregate local secrets across environments. 1Password-backed envs are
      // skipped here so opening a vault doesn't shell out to `op` for every
      // linked env; their secrets are fetched on demand when selected.
      let mut all = Vec::new();
      for e in super::environment::list(vault_id)? {
        if e.op_item.is_some() {
          continue;
        }
        all.extend(list(vault_id, Some(&e.name))?);
      }
      return Ok(all);
    }
  };

  if let Some(cfg) = super::environment::op_config(vault_id, env)? {
    return list_op(vault_id, env, &cfg);
  }

  let mut conn = super::conn()?;
  let vault_key = session::get_vault_key(vault_id)?;

  let rows: Vec<SecretRow> = sql_query(
    "SELECT id, vault_id, environment, encrypted_key, encrypted_value, key_nonce, value_nonce, created_at, updated_at
     FROM secrets WHERE vault_id = ? AND environment = ?",
  )
  .bind::<Text, _>(vault_id)
  .bind::<Text, _>(env)
  .load(&mut conn)?;

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
      inherited: false,
    });
  }

  Ok(secrets)
}

/// Lists secrets for an environment resolved against its inheritance chain:
/// values from parent environments are included, and any key also defined in a
/// more derived environment overrides the inherited one. The `environment`
/// field of each entry reflects where the value is actually defined, and
/// `inherited` is true when that is an ancestor of `environment_name`.
pub fn list_resolved(
  vault_id: &str,
  environment_name: &str,
) -> Result<Vec<SecretResponse>> {
  let chain = super::environment::resolve_chain(vault_id, environment_name)?;

  // Walk root -> target so more derived environments overwrite ancestors.
  let mut merged: std::collections::HashMap<String, SecretResponse> =
    std::collections::HashMap::new();

  for env in &chain {
    for mut secret in list(vault_id, Some(env))? {
      secret.inherited = env != environment_name;
      merged.insert(secret.key.clone(), secret);
    }
  }

  let mut resolved: Vec<SecretResponse> = merged.into_values().collect();
  resolved.sort_by(|a, b| a.key.cmp(&b.key));
  Ok(resolved)
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

  if let Some(cfg) = super::environment::op_config(vault_id, environment)? {
    let token = crate::keychain::get_op_token(&cfg.env_id)?;
    crate::op::set_field(&token, &cfg.op_vault, &cfg.op_item, key, value)?;
    return Ok(());
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

  let _ = super::api_key::resync_env_and_descendants(vault_id, environment);

  Ok(())
}

pub fn update(id: &str, value: &str) -> Result<()> {
  if let Some((env_id, key)) = parse_op_secret_id(id) {
    let cfg = super::environment::op_config_by_id(&env_id)?
      .ok_or_else(|| anyhow::anyhow!("Environment is not 1Password-backed"))?;
    let token = crate::keychain::get_op_token(&cfg.env_id)?;
    crate::op::set_field(&token, &cfg.op_vault, &cfg.op_item, &key, value)?;
    return Ok(());
  }

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

  let _ = super::api_key::resync_env_and_descendants(&vault_id, &environment);

  Ok(())
}

pub fn delete(id: &str) -> Result<()> {
  if let Some((env_id, key)) = parse_op_secret_id(id) {
    let cfg = super::environment::op_config_by_id(&env_id)?
      .ok_or_else(|| anyhow::anyhow!("Environment is not 1Password-backed"))?;
    let token = crate::keychain::get_op_token(&cfg.env_id)?;
    crate::op::delete_field(&token, &cfg.op_vault, &cfg.op_item, &key)?;
    return Ok(());
  }

  let mut conn = super::conn()?;

  let rows: Vec<SecretDataRow> =
    sql_query("SELECT vault_id, environment FROM secrets WHERE id = ?")
      .bind::<Text, _>(id)
      .load(&mut conn)?;
  let location = rows
    .first()
    .map(|r| (r.vault_id.clone(), r.environment.clone()));

  sql_query("DELETE FROM secrets WHERE id = ?")
    .bind::<Text, _>(id)
    .execute(&mut conn)?;

  let _ = super::api_key::delete_for_secret(id);

  if let Some((vault_id, environment)) = location {
    let _ = super::api_key::resync_env_and_descendants(&vault_id, &environment);
  }

  Ok(())
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn test_op_secret_id_round_trip() {
    let env_id = "550e8400-e29b-41d4-a716-446655440000";
    let id = op_secret_id(env_id, "API_KEY");
    assert_eq!(
      parse_op_secret_id(&id),
      Some((env_id.into(), "API_KEY".into()))
    );

    // Keys may contain ':' since the env id is a colonless UUID.
    let id = op_secret_id(env_id, "weird:key:name");
    assert_eq!(
      parse_op_secret_id(&id),
      Some((env_id.into(), "weird:key:name".into()))
    );
  }

  #[test]
  fn test_parse_op_secret_id_ignores_local_ids() {
    assert_eq!(
      parse_op_secret_id("550e8400-e29b-41d4-a716-446655440000"),
      None
    );
    assert_eq!(parse_op_secret_id("not-an-op-id"), None);
  }
}
