use anyhow::Result;

#[cfg(target_os = "macos")]
mod security_framework_impl {
  use super::*;
  use security_framework::os::macos::keychain::SecKeychain;

  const SERVICE_NAME: &str = "dev.vault0.secretkey";
  const ACCOUNT_NAME: &str = "master";

  pub fn save_secret_key(secret_key_hex: &str) -> Result<()> {
    let _ = delete_secret_key();
    SecKeychain::default()?.add_generic_password(
      SERVICE_NAME,
      ACCOUNT_NAME,
      secret_key_hex.as_bytes(),
    )?;

    Ok(())
  }

  pub fn get_secret_key() -> Result<String> {
    let (password, _) = SecKeychain::default()?
      .find_generic_password(SERVICE_NAME, ACCOUNT_NAME)
      .map_err(|_| anyhow::anyhow!("Secret key not found in Keychain"))?;

    Ok(String::from_utf8(password.to_vec())?)
  }

  pub fn delete_secret_key() -> Result<()> {
    let keychain = SecKeychain::default()?;

    if let Ok((_, item)) =
      keychain.find_generic_password(SERVICE_NAME, ACCOUNT_NAME)
    {
      item.delete();
    }
    Ok(())
  }

  #[allow(dead_code)]
  pub fn has_secret_key() -> bool {
    SecKeychain::default()
      .and_then(|kc| kc.find_generic_password(SERVICE_NAME, ACCOUNT_NAME))
      .is_ok()
  }

  // Per-environment 1Password service account token. One keychain item per
  // environment id so tokens can differ across environments.
  const OP_TOKEN_ACCOUNT: &str = "service_account";

  fn op_token_service(environment_id: &str) -> String {
    format!("dev.vault0.op_token.{}", environment_id)
  }

  pub fn save_op_token(environment_id: &str, token: &str) -> Result<()> {
    let _ = delete_op_token(environment_id);
    SecKeychain::default()?.add_generic_password(
      &op_token_service(environment_id),
      OP_TOKEN_ACCOUNT,
      token.as_bytes(),
    )?;
    Ok(())
  }

  pub fn get_op_token(environment_id: &str) -> Result<String> {
    let (password, _) = SecKeychain::default()?
      .find_generic_password(&op_token_service(environment_id), OP_TOKEN_ACCOUNT)
      .map_err(|_| {
        anyhow::anyhow!(
          "1Password token not found for this environment. Re-configure 1Password."
        )
      })?;
    Ok(String::from_utf8(password.to_vec())?)
  }

  pub fn delete_op_token(environment_id: &str) -> Result<()> {
    let keychain = SecKeychain::default()?;
    if let Ok((_, item)) = keychain.find_generic_password(
      &op_token_service(environment_id),
      OP_TOKEN_ACCOUNT,
    ) {
      item.delete();
    }
    Ok(())
  }
}

#[cfg(target_os = "macos")]
pub use security_framework_impl::*;

#[cfg(not(target_os = "macos"))]
pub fn save_secret_key(_secret_key_hex: &str) -> Result<()> {
  bail!("Keychain access is only supported on macOS")
}

#[cfg(not(target_os = "macos"))]
pub fn get_secret_key() -> Result<String> {
  bail!("Secret key not found")
}

#[cfg(not(target_os = "macos"))]
pub fn delete_secret_key() -> Result<()> {
  Ok(())
}

#[cfg(not(target_os = "macos"))]
pub fn has_secret_key() -> bool {
  false
}

#[cfg(not(target_os = "macos"))]
pub fn save_op_token(_environment_id: &str, _token: &str) -> Result<()> {
  anyhow::bail!("Keychain access is only supported on macOS")
}

#[cfg(not(target_os = "macos"))]
pub fn get_op_token(_environment_id: &str) -> Result<String> {
  anyhow::bail!("1Password token not found")
}

#[cfg(not(target_os = "macos"))]
pub fn delete_op_token(_environment_id: &str) -> Result<()> {
  Ok(())
}
