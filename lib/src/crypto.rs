use aes_gcm::aead::{Aead, KeyInit, OsRng};
use aes_gcm::{Aes256Gcm, Key, Nonce};
use anyhow::{bail, Result};
use argon2::password_hash::{PasswordHasher, SaltString};
use argon2::{Algorithm, Argon2, Params, Version};
use p256::ecdsa::{SigningKey, VerifyingKey};
use rand::RngCore;
use zeroize::{Zeroize, ZeroizeOnDrop};

#[derive(Clone, Zeroize, ZeroizeOnDrop)]
pub struct MasterKey([u8; 32]);

impl MasterKey {
  pub fn as_bytes(&self) -> &[u8; 32] {
    &self.0
  }

  #[cfg(test)]
  pub fn from_bytes(bytes: [u8; 32]) -> Self {
    MasterKey(bytes)
  }
}

#[derive(Clone, Zeroize, ZeroizeOnDrop)]
pub struct VaultKey([u8; 32]);

impl VaultKey {
  pub fn as_bytes(&self) -> &[u8; 32] {
    &self.0
  }

  pub fn from_bytes(bytes: [u8; 32]) -> Self {
    VaultKey(bytes)
  }
}

#[derive(Clone)]
pub struct EncryptedData {
  pub ciphertext: Vec<u8>,
  pub nonce: [u8; 12],
}

#[derive(Clone, Debug)]
pub struct Argon2Params {
  pub mem_cost: u32,
  pub time_cost: u32,
  pub parallelism: u32,
}

impl Default for Argon2Params {
  fn default() -> Self {
    Argon2Params {
      mem_cost: 131072,
      time_cost: 4,
      parallelism: 4,
    }
  }
}

pub fn derive_master_key(
  password: &str,
  secret_code: &[u8],
  salt: &[u8],
  params: &Argon2Params,
) -> Result<MasterKey> {
  if salt.len() != 32 {
    bail!("Salt must be 32 bytes, got {}", salt.len());
  }

  if secret_code.len() != 32 {
    bail!("Secret code must be 32 bytes, got {}", secret_code.len());
  }

  let argon2_params =
    Params::new(params.mem_cost, params.time_cost, params.parallelism, None)
      .map_err(|e| anyhow::anyhow!("Invalid Argon2 params: {}", e))?;
  let argon2 = Argon2::new(Algorithm::Argon2id, Version::V0x13, argon2_params);

  let salt_string = SaltString::encode_b64(salt)
    .map_err(|e| anyhow::anyhow!("Failed to encode salt: {}", e))?;

  let mut combined_input =
    Vec::with_capacity(password.len() + secret_code.len());
  combined_input.extend_from_slice(password.as_bytes());
  combined_input.extend_from_slice(secret_code);

  let password_hash = argon2
    .hash_password(&combined_input, &salt_string)
    .map_err(|e| anyhow::anyhow!("Failed to hash password: {}", e))?;

  let hash_bytes = password_hash
    .hash
    .ok_or_else(|| anyhow::anyhow!("No hash output from Argon2"))?;

  let key_bytes = hash_bytes.as_bytes();
  if key_bytes.len() < 32 {
    bail!("Argon2 output too short: {} bytes", key_bytes.len());
  }

  let mut master_key = [0u8; 32];
  master_key.copy_from_slice(&key_bytes[..32]);

  Ok(MasterKey(master_key))
}

pub fn generate_secret_code() -> [u8; 32] {
  let mut key = [0u8; 32];
  OsRng.fill_bytes(&mut key);
  key
}

pub fn generate_vault_key() -> VaultKey {
  let mut key = [0u8; 32];
  OsRng.fill_bytes(&mut key);
  VaultKey(key)
}

pub fn encrypt_data(key: &[u8; 32], plaintext: &[u8]) -> Result<EncryptedData> {
  let cipher = Aes256Gcm::new(Key::<Aes256Gcm>::from_slice(key));
  let nonce_bytes = generate_nonce();
  let nonce = Nonce::from_slice(&nonce_bytes);
  let ciphertext = cipher
    .encrypt(nonce, plaintext)
    .map_err(|e| anyhow::anyhow!("AES-GCM encryption failed: {}", e))?;

  Ok(EncryptedData {
    ciphertext,
    nonce: nonce_bytes,
  })
}

pub fn decrypt_data(
  key: &[u8; 32],
  encrypted: &EncryptedData,
) -> Result<Vec<u8>> {
  let cipher = Aes256Gcm::new(Key::<Aes256Gcm>::from_slice(key));
  let nonce = Nonce::from_slice(&encrypted.nonce);
  let plaintext = cipher
    .decrypt(nonce, encrypted.ciphertext.as_slice())
    .map_err(|e| anyhow::anyhow!("AES-GCM decryption failed: {}", e))?;

  Ok(plaintext)
}

fn generate_nonce() -> [u8; 12] {
  let mut nonce = [0u8; 12];
  OsRng.fill_bytes(&mut nonce);
  nonce
}

pub fn generate_salt() -> [u8; 32] {
  let mut salt = [0u8; 32];
  OsRng.fill_bytes(&mut salt);
  salt
}

pub fn derive_key(
  password: &str,
  salt: &[u8; 32],
  params: &Argon2Params,
) -> Result<[u8; 32]> {
  let argon2_params =
    Params::new(params.mem_cost, params.time_cost, params.parallelism, None)
      .map_err(|e| anyhow::anyhow!("Invalid Argon2 params: {}", e))?;
  let argon2 = Argon2::new(Algorithm::Argon2id, Version::V0x13, argon2_params);

  let salt_string = SaltString::encode_b64(salt)
    .map_err(|e| anyhow::anyhow!("Failed to encode salt: {}", e))?;

  let password_hash =
    argon2
      .hash_password(password.as_bytes(), &salt_string)
      .map_err(|e| anyhow::anyhow!("Failed to hash password: {}", e))?;

  let hash_bytes = password_hash
    .hash
    .ok_or_else(|| anyhow::anyhow!("No hash output from Argon2"))?;

  let key_bytes = hash_bytes.as_bytes();
  if key_bytes.len() < 32 {
    bail!("Argon2 output too short: {} bytes", key_bytes.len());
  }

  let mut key = [0u8; 32];
  key.copy_from_slice(&key_bytes[..32]);

  Ok(key)
}

pub struct EcdsaKeyPair {
  pub private_key: SigningKey,
  pub public_key: VerifyingKey,
}

pub fn generate_ecdsa_keypair() -> EcdsaKeyPair {
  let private_key = SigningKey::random(&mut OsRng);
  let public_key = VerifyingKey::from(&private_key);

  EcdsaKeyPair {
    private_key,
    public_key,
  }
}

pub fn deserialize_ecdsa_private_key(bytes: &[u8]) -> Result<SigningKey> {
  if bytes.len() != 32 {
    bail!(
      "Invalid private key length: expected 32 bytes, got {}",
      bytes.len()
    );
  }

  let mut key_bytes = [0u8; 32];
  key_bytes.copy_from_slice(bytes);

  SigningKey::from_bytes(&key_bytes.into())
    .map_err(|e| anyhow::anyhow!("Failed to deserialize private key: {}", e))
}

pub fn deserialize_ecdsa_public_key(bytes: &[u8]) -> Result<VerifyingKey> {
  use p256::EncodedPoint;

  let point = EncodedPoint::from_bytes(bytes)
    .map_err(|e| anyhow::anyhow!("Failed to parse public key: {}", e))?;

  VerifyingKey::from_encoded_point(&point)
    .map_err(|e| anyhow::anyhow!("Failed to deserialize public key: {}", e))
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn test_key_derivation() {
    let password = "test_password_123";
    let secret_key = generate_secret_code();
    let salt = generate_salt();
    let params = Argon2Params::default();

    let key1 =
      derive_master_key(password, &secret_key, &salt, &params).unwrap();
    let key2 =
      derive_master_key(password, &secret_key, &salt, &params).unwrap();

    assert_eq!(key1.as_bytes(), key2.as_bytes());
  }

  #[test]
  fn test_key_derivation_different_salts() {
    let password = "test_password_123";
    let secret_code = generate_secret_code();
    let salt1 = generate_salt();
    let salt2 = generate_salt();
    let params = Argon2Params::default();

    let key1 =
      derive_master_key(password, &secret_code, &salt1, &params).unwrap();
    let key2 =
      derive_master_key(password, &secret_code, &salt2, &params).unwrap();

    assert_ne!(key1.as_bytes(), key2.as_bytes());
  }

  #[test]
  fn test_key_derivation_different_secret_keys() {
    let password = "test_password_123";
    let secret_code1 = generate_secret_code();
    let secret_code2 = generate_secret_code();
    let salt = generate_salt();
    let params = Argon2Params::default();

    let key1 =
      derive_master_key(password, &secret_code1, &salt, &params).unwrap();
    let key2 =
      derive_master_key(password, &secret_code2, &salt, &params).unwrap();

    assert_ne!(key1.as_bytes(), key2.as_bytes());
  }

  #[test]
  fn test_encryption_decryption() {
    let key = [0x42; 32];
    let plaintext = b"Hello, World! This is a secret message.";

    let encrypted = encrypt_data(&key, plaintext).unwrap();
    let decrypted = decrypt_data(&key, &encrypted).unwrap();

    assert_eq!(plaintext, decrypted.as_slice());
  }

  #[test]
  fn test_encryption_unique_nonces() {
    let key = [0x42; 32];
    let plaintext = b"Same message";

    let encrypted1 = encrypt_data(&key, plaintext).unwrap();
    let encrypted2 = encrypt_data(&key, plaintext).unwrap();

    assert_ne!(encrypted1.nonce, encrypted2.nonce);
    assert_ne!(encrypted1.ciphertext, encrypted2.ciphertext);
  }

  #[test]
  fn test_decryption_wrong_key() {
    let key1 = [0x42; 32];
    let key2 = [0x43; 32];
    let plaintext = b"Secret message";

    let encrypted = encrypt_data(&key1, plaintext).unwrap();
    let result = decrypt_data(&key2, &encrypted);

    assert!(result.is_err());
  }

  #[test]
  fn test_decryption_tampered_ciphertext() {
    let key = [0x42; 32];
    let plaintext = b"Secret message";

    let mut encrypted = encrypt_data(&key, plaintext).unwrap();

    if !encrypted.ciphertext.is_empty() {
      encrypted.ciphertext[0] ^= 0xFF;
    }

    let result = decrypt_data(&key, &encrypted);

    assert!(result.is_err());
  }
}
