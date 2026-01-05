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

  const ECDSA_SERVICE_NAME: &str = "dev.vault0.ecdsa_private_key";
  const ECDSA_ACCOUNT_NAME: &str = "master";

  pub fn save_ecdsa_private_key(encrypted_key_hex: &str) -> Result<()> {
    let _ = delete_ecdsa_private_key();
    SecKeychain::default()?.add_generic_password(
      ECDSA_SERVICE_NAME,
      ECDSA_ACCOUNT_NAME,
      encrypted_key_hex.as_bytes(),
    )?;

    Ok(())
  }

  pub fn get_ecdsa_private_key() -> Result<String> {
    let (password, _) = SecKeychain::default()?
      .find_generic_password(ECDSA_SERVICE_NAME, ECDSA_ACCOUNT_NAME)
      .map_err(|_| anyhow::anyhow!("ECDSA key not found in Keychain"))?;

    Ok(String::from_utf8(password.to_vec())?)
  }

  pub fn delete_ecdsa_private_key() -> Result<()> {
    let keychain = SecKeychain::default()?;

    if let Ok((_, item)) =
      keychain.find_generic_password(ECDSA_SERVICE_NAME, ECDSA_ACCOUNT_NAME)
    {
      item.delete();
    }
    Ok(())
  }

  pub fn has_ecdsa_private_key() -> bool {
    SecKeychain::default()
      .and_then(|kc| {
        kc.find_generic_password(ECDSA_SERVICE_NAME, ECDSA_ACCOUNT_NAME)
      })
      .is_ok()
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
pub fn save_ecdsa_private_key(_encrypted_key_hex: &str) -> Result<()> {
  bail!("Keychain access is only supported on macOS")
}

#[cfg(not(target_os = "macos"))]
pub fn get_ecdsa_private_key() -> Result<String> {
  bail!("ECDSA key not found")
}

#[cfg(not(target_os = "macos"))]
pub fn delete_ecdsa_private_key() -> Result<()> {
  Ok(())
}

#[cfg(not(target_os = "macos"))]
pub fn has_ecdsa_private_key() -> bool {
  false
}
