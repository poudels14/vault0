use anyhow::{bail, Context, Result};
use diesel::prelude::*;
use diesel::sql_query;
use diesel::sql_types::{BigInt, Binary, Text};

use crate::crypto::{self, MasterKey};
use crate::keychain;
use crate::session;

#[derive(QueryableByName)]
struct CountRow {
  #[diesel(sql_type = BigInt)]
  count: i64,
}

#[derive(QueryableByName)]
struct PasswordHashRow {
  #[diesel(sql_type = Text)]
  password_hash: String,
}

#[derive(QueryableByName)]
struct SaltRow {
  #[diesel(sql_type = Binary)]
  salt: Vec<u8>,
}

#[derive(QueryableByName)]
struct SecretCodeSaltRow {
  #[diesel(sql_type = Binary)]
  secret_code_salt: Vec<u8>,
}

pub fn has_master_password() -> bool {
  let mut conn = match super::conn() {
    Ok(c) => c,
    Err(_) => return false,
  };

  let result: Result<Vec<CountRow>, _> =
    sql_query("SELECT COUNT(*) as count FROM master_passwords").load(&mut conn);

  match result {
    Ok(rows) => rows.first().map(|r| r.count > 0).unwrap_or(false),
    Err(_) => false,
  }
}

pub fn create_master_password(password: &str) -> Result<String> {
  let mut conn = super::conn()?;

  let hash = bcrypt::hash(password, bcrypt::DEFAULT_COST)?;

  let secret_code = crypto::generate_secret_code();
  let secret_code_salt = crypto::generate_salt();
  let params = crypto::Argon2Params::default();

  let encryption_key =
    crypto::derive_key(password, &secret_code_salt, &params)?;
  let encrypted_secret_code =
    crypto::encrypt_data(&encryption_key, &secret_code)?;

  let mut encrypted_with_nonce = Vec::new();
  encrypted_with_nonce.extend_from_slice(&encrypted_secret_code.nonce);
  encrypted_with_nonce.extend_from_slice(&encrypted_secret_code.ciphertext);

  keychain::save_secret_key(&hex::encode(&encrypted_with_nonce))?;

  let master_key_salt = crypto::generate_salt();
  let master_key = crypto::derive_master_key(
    password,
    &secret_code,
    &master_key_salt,
    &params,
  )?;

  let ecdsa_keypair = crypto::generate_ecdsa_keypair();
  let ecdsa_private_key_bytes = &ecdsa_keypair.private_key.to_bytes().to_vec();
  let ecdsa_public_key_bytes = &ecdsa_keypair
    .public_key
    .to_encoded_point(true)
    .as_bytes()
    .to_vec();

  let encrypted_ecdsa_private =
    crypto::encrypt_data(master_key.as_bytes(), ecdsa_private_key_bytes)?;

  let mut encrypted_ecdsa_with_nonce = Vec::new();
  encrypted_ecdsa_with_nonce.extend_from_slice(&encrypted_ecdsa_private.nonce);
  encrypted_ecdsa_with_nonce
    .extend_from_slice(&encrypted_ecdsa_private.ciphertext);

  keychain::save_ecdsa_private_key(&hex::encode(&encrypted_ecdsa_with_nonce))?;

  let now = chrono::Utc::now().timestamp();
  sql_query(
    "INSERT INTO master_passwords (id, password_hash, secret_code_salt, master_key_salt, ecdsa_public_key, created_at, updated_at) VALUES (1, ?, ?, ?, ?, ?, ?)",
  )
  .bind::<Text, _>(&hash)
  .bind::<Binary, _>(secret_code_salt.as_slice())
  .bind::<Binary, _>(master_key_salt.as_slice())
  .bind::<Binary, _>(ecdsa_public_key_bytes.as_slice())
  .bind::<BigInt, _>(now)
  .bind::<BigInt, _>(now)
  .execute(&mut conn)?;

  session::init_session(master_key)?;

  Ok(hex::encode(secret_code))
}

pub fn verify_password(password: &str) -> Result<()> {
  let mut conn = super::conn()?;

  let rows: Vec<PasswordHashRow> =
    sql_query("SELECT password_hash FROM master_passwords WHERE id = 1")
      .load(&mut conn)?;

  let row = rows.first().context("Master password not found")?;
  let hash = &row.password_hash;

  if !bcrypt::verify(password, hash).unwrap_or(false) {
    bail!("Invalid password");
  }

  Ok(())
}

pub fn get_master_key(password: &str) -> Result<MasterKey> {
  verify_password(password)?;

  let mut conn = super::conn()?;

  let rows: Vec<SecretCodeSaltRow> =
    sql_query("SELECT secret_code_salt FROM master_passwords WHERE id = 1")
      .load(&mut conn)?;

  let row = rows.first().context("Encryption salt not found")?;
  let encryption_salt: [u8; 32] = row
    .secret_code_salt
    .clone()
    .try_into()
    .map_err(|_| anyhow::anyhow!("Invalid encryption salt"))?;

  let params = crypto::Argon2Params::default();
  let encryption_key = crypto::derive_key(password, &encryption_salt, &params)?;

  let encrypted_secret_code_hex = keychain::get_secret_key()?;
  let encrypted_with_nonce = hex::decode(&encrypted_secret_code_hex)?;

  if encrypted_with_nonce.len() <= 12 {
    bail!("Invalid encrypted secret code format");
  }

  let nonce: [u8; 12] = encrypted_with_nonce[..12]
    .try_into()
    .map_err(|_| anyhow::anyhow!("Invalid nonce"))?;

  let encrypted_data = crypto::EncryptedData {
    ciphertext: encrypted_with_nonce[12..].to_vec(),
    nonce,
  };

  let secret_code_bytes =
    crypto::decrypt_data(&encryption_key, &encrypted_data)?;
  let secret_code: [u8; 32] = secret_code_bytes
    .try_into()
    .map_err(|_| anyhow::anyhow!("Invalid secret code length"))?;

  let rows: Vec<SaltRow> = sql_query(
    "SELECT master_key_salt as salt FROM master_passwords WHERE id = 1",
  )
  .load(&mut conn)?;

  let row = rows.first().context("Salt not found")?;
  let salt: [u8; 32] = row
    .salt
    .clone()
    .try_into()
    .map_err(|_| anyhow::anyhow!("Invalid salt"))?;

  let master_key =
    crypto::derive_master_key(password, &secret_code, &salt, &params)?;

  if !keychain::has_ecdsa_private_key() {
    generate_missing_ecdsa_keys(&master_key)?;
  }

  Ok(master_key)
}

fn generate_missing_ecdsa_keys(master_key: &MasterKey) -> Result<()> {
  let mut conn = super::conn()?;

  let ecdsa_keypair = crypto::generate_ecdsa_keypair();
  let ecdsa_private_key_bytes = &ecdsa_keypair.private_key.to_bytes().to_vec();
  let ecdsa_public_key_bytes = &ecdsa_keypair
    .public_key
    .to_encoded_point(true)
    .as_bytes()
    .to_vec();

  let encrypted_ecdsa_private =
    crypto::encrypt_data(master_key.as_bytes(), ecdsa_private_key_bytes)?;

  let mut encrypted_ecdsa_with_nonce = Vec::new();
  encrypted_ecdsa_with_nonce.extend_from_slice(&encrypted_ecdsa_private.nonce);
  encrypted_ecdsa_with_nonce
    .extend_from_slice(&encrypted_ecdsa_private.ciphertext);

  keychain::save_ecdsa_private_key(&hex::encode(&encrypted_ecdsa_with_nonce))?;

  let now = chrono::Utc::now().timestamp();
  sql_query(
    "UPDATE master_passwords SET ecdsa_public_key = ?, updated_at = ? WHERE id = 1",
  )
  .bind::<Binary, _>(ecdsa_public_key_bytes.as_slice())
  .bind::<BigInt, _>(now)
  .execute(&mut conn)?;

  Ok(())
}
