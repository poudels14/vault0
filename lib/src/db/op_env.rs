use anyhow::Result;
use diesel::prelude::*;
use diesel::sql_query;
use diesel::sql_types::Text;

use super::environment;

/// Configures an environment to be backed by 1Password: stores the service
/// account token in the Keychain, pushes the environment's existing local
/// secrets into the chosen 1Password item, deletes the local copies, and marks
/// the environment op-backed. After this, all secret reads/writes for the
/// environment go through the `op` CLI.
pub fn configure(
  vault_id: &str,
  env_name: &str,
  token: &str,
  op_vault: &str,
  op_item: &str,
) -> Result<()> {
  crate::op::ensure_available()?;

  let env_id = environment::id_for(vault_id, env_name)?;
  crate::keychain::save_op_token(&env_id, token)?;

  // Read the environment's existing local secrets (it is not op-backed yet, so
  // this hits the sqlite path) and push them into the 1Password item.
  let existing = super::secret::list(vault_id, Some(env_name))?;
  for secret in &existing {
    crate::op::set_field(token, op_vault, op_item, &secret.key, &secret.value)?;
  }

  // 1Password is now the source of truth; drop the local copies.
  delete_local_secrets(vault_id, env_name)?;

  environment::set_op_config(vault_id, env_name, op_vault, op_item)?;
  Ok(())
}

/// Updates the token and/or 1Password vault/item for an already op-backed
/// environment.
pub fn update_config(
  vault_id: &str,
  env_name: &str,
  token: &str,
  op_vault: &str,
  op_item: &str,
) -> Result<()> {
  crate::op::ensure_available()?;
  let env_id = environment::id_for(vault_id, env_name)?;
  crate::keychain::save_op_token(&env_id, token)?;
  environment::set_op_config(vault_id, env_name, op_vault, op_item)?;
  Ok(())
}

/// Reverts an op-backed environment to local storage: pulls the current
/// 1Password values back into sqlite, clears the op config, and removes the
/// stored token.
pub fn clear_config(vault_id: &str, env_name: &str) -> Result<()> {
  let Some(cfg) = environment::op_config(vault_id, env_name)? else {
    return Ok(());
  };

  let fields = match crate::keychain::get_op_token(&cfg.env_id) {
    Ok(token) => crate::op::get_fields(&token, &cfg.op_vault, &cfg.op_item)
      .unwrap_or_default(),
    Err(_) => Vec::new(),
  };

  environment::clear_op_config(vault_id, env_name)?;

  for (key, value) in fields {
    let _ = super::secret::create(vault_id, env_name, &key, &value);
  }

  let _ = crate::keychain::delete_op_token(&cfg.env_id);
  Ok(())
}

fn delete_local_secrets(vault_id: &str, env_name: &str) -> Result<()> {
  let mut conn = super::conn()?;

  sql_query("DELETE FROM secrets WHERE vault_id = ? AND environment = ?")
    .bind::<Text, _>(vault_id)
    .bind::<Text, _>(env_name)
    .execute(&mut conn)?;

  Ok(())
}
