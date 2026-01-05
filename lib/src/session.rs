use std::collections::HashMap;
use std::sync::{Arc, OnceLock, RwLock};

use anyhow::Result;

use crate::crypto::{MasterKey, VaultKey};

struct SessionKeyCache {
  master_key: Option<MasterKey>,
  vault_keys: HashMap<String, VaultKey>,
}

impl SessionKeyCache {
  fn new() -> Self {
    SessionKeyCache {
      master_key: None,
      vault_keys: HashMap::new(),
    }
  }
}

static SESSION_CACHE: OnceLock<Arc<RwLock<SessionKeyCache>>> = OnceLock::new();

fn get_session_cache() -> Arc<RwLock<SessionKeyCache>> {
  SESSION_CACHE
    .get_or_init(|| Arc::new(RwLock::new(SessionKeyCache::new())))
    .clone()
}

pub fn init_session(master_key: MasterKey) -> Result<()> {
  let cache = get_session_cache();
  let mut session = cache.write().unwrap();

  session.vault_keys.clear();
  session.master_key = Some(master_key);

  Ok(())
}

pub fn get_master_key() -> Result<MasterKey> {
  let cache = get_session_cache();
  let session = cache.read().unwrap();

  session
    .master_key
    .as_ref()
    .map(|k| k.clone())
    .ok_or_else(|| anyhow::anyhow!("Session not initialized"))
}

pub fn get_vault_key(vault_id: &str) -> Result<VaultKey> {
  let cache = get_session_cache();

  {
    let session = cache.read().unwrap();
    if let Some(key) = session.vault_keys.get(vault_id) {
      return Ok(key.clone());
    }
  }

  let vault_key = crate::db::vault_key::get_or_create(vault_id)?;

  {
    let mut session = cache.write().unwrap();
    session
      .vault_keys
      .insert(vault_id.to_string(), vault_key.clone());
  }

  Ok(vault_key)
}

pub fn clear_session() {
  let cache = get_session_cache();
  let mut session = cache.write().unwrap();

  session.master_key = None;
  session.vault_keys.clear();
}

#[cfg(test)]
pub fn is_session_active() -> bool {
  let cache = get_session_cache();
  let session = cache.read().unwrap();
  session.master_key.is_some()
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::crypto::MasterKey;

  #[test]
  fn test_session_lifecycle() {
    clear_session();

    assert!(!is_session_active());

    let master_key = MasterKey::from_bytes([0x42; 32]);
    init_session(master_key).unwrap();

    assert!(is_session_active());

    let retrieved_key = get_master_key().unwrap();
    assert_eq!(retrieved_key.as_bytes(), &[0x42; 32]);

    clear_session();

    assert!(!is_session_active());
    assert!(get_master_key().is_err());
  }
}
