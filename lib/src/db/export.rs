use anyhow::{bail, Context, Result};
use base64::{engine::general_purpose, Engine as _};
use serde::{Deserialize, Serialize};

use crate::crypto::{self, Argon2Params};
use crate::models::{
  ImportEnvironmentPreview, ImportPreview, ImportResolution, ImportResult,
  ImportVaultPreview,
};

const EXPORT_FORMAT: &str = "vault0-export";
const EXPORT_VERSION: u32 = 2;

// Stronger than the app default KDF; export files may be attacked offline.
fn export_kdf_params() -> Argon2Params {
  Argon2Params {
    mem_cost: 524_288, // 512 MiB
    time_cost: 6,
    parallelism: 4,
  }
}

#[derive(Serialize, Deserialize)]
struct Envelope {
  format: String,
  version: u32,
  kdf: Kdf,
  cipher: String,
  nonce: String,
  ciphertext: String,
}

#[derive(Serialize, Deserialize)]
struct Kdf {
  algorithm: String,
  salt: String,
  mem_cost: u32,
  time_cost: u32,
  parallelism: u32,
}

#[derive(Serialize, Deserialize)]
struct Payload {
  vaults: Vec<VaultExport>,
  exported_at: i64,
}

#[derive(Serialize, Deserialize)]
struct VaultExport {
  name: String,
  description: Option<String>,
  environments: Vec<EnvPayload>,
}

#[derive(Serialize, Deserialize)]
struct EnvPayload {
  name: String,
  display_order: i64,
  secrets: Vec<SecretPair>,
}

#[derive(Serialize, Deserialize)]
struct SecretPair {
  key: String,
  value: String,
}

// Version 1 payload: a single vault. Kept for importing older export files.
#[derive(Deserialize)]
struct PayloadV1 {
  vault: VaultMetaV1,
  environments: Vec<EnvPayload>,
}

#[derive(Deserialize)]
struct VaultMetaV1 {
  name: String,
  description: Option<String>,
}

pub fn export_vaults(
  vault_ids: &[String],
  export_password: &str,
) -> Result<String> {
  let all = super::vault::list()?;
  let mut vaults = Vec::new();

  for vault_id in vault_ids {
    let vault = all
      .iter()
      .find(|v| &v.id == vault_id)
      .context("Vault not found")?;

    let mut environments = Vec::new();
    for env in super::environment::list(vault_id)? {
      let secrets = super::secret::list(vault_id, Some(&env.name))?
        .into_iter()
        .map(|s| SecretPair {
          key: s.key,
          value: s.value,
        })
        .collect();

      environments.push(EnvPayload {
        name: env.name,
        display_order: env.display_order,
        secrets,
      });
    }

    vaults.push(VaultExport {
      name: vault.name.clone(),
      description: vault.description.clone(),
      environments,
    });
  }

  let payload = Payload {
    vaults,
    exported_at: chrono::Utc::now().timestamp(),
  };

  seal_payload(&payload, export_password, &export_kdf_params())
}

fn seal_payload(
  payload: &Payload,
  export_password: &str,
  params: &Argon2Params,
) -> Result<String> {
  let plaintext = serde_json::to_vec(payload)?;

  let salt = crypto::generate_salt();
  let key = crypto::derive_key(export_password, &salt, params)?;
  let encrypted = crypto::encrypt_data(&key, &plaintext)?;

  let envelope = Envelope {
    format: EXPORT_FORMAT.to_string(),
    version: EXPORT_VERSION,
    kdf: Kdf {
      algorithm: "argon2id".to_string(),
      salt: general_purpose::STANDARD.encode(salt),
      mem_cost: params.mem_cost,
      time_cost: params.time_cost,
      parallelism: params.parallelism,
    },
    cipher: "aes-256-gcm".to_string(),
    nonce: general_purpose::STANDARD.encode(encrypted.nonce),
    ciphertext: general_purpose::STANDARD.encode(&encrypted.ciphertext),
  };

  Ok(serde_json::to_string_pretty(&envelope)?)
}

fn decrypt_payload(
  envelope_json: &str,
  export_password: &str,
) -> Result<Payload> {
  let envelope: Envelope = serde_json::from_str(envelope_json)
    .context("Not a valid vault0 export file")?;

  if envelope.format != EXPORT_FORMAT {
    bail!("Not a valid vault0 export file");
  }
  if envelope.version == 0 || envelope.version > EXPORT_VERSION {
    bail!("Unsupported export version: {}", envelope.version);
  }

  let salt_bytes = general_purpose::STANDARD
    .decode(&envelope.kdf.salt)
    .context("Corrupt export file")?;
  let salt: [u8; 32] = salt_bytes
    .as_slice()
    .try_into()
    .map_err(|_| anyhow::anyhow!("Corrupt export file"))?;

  let nonce_bytes = general_purpose::STANDARD
    .decode(&envelope.nonce)
    .context("Corrupt export file")?;
  let nonce: [u8; 12] = nonce_bytes
    .as_slice()
    .try_into()
    .map_err(|_| anyhow::anyhow!("Corrupt export file"))?;

  let ciphertext = general_purpose::STANDARD
    .decode(&envelope.ciphertext)
    .context("Corrupt export file")?;

  let params = Argon2Params {
    mem_cost: envelope.kdf.mem_cost,
    time_cost: envelope.kdf.time_cost,
    parallelism: envelope.kdf.parallelism,
  };
  let key = crypto::derive_key(export_password, &salt, &params)?;

  let plaintext =
    crypto::decrypt_data(&key, &crypto::EncryptedData { ciphertext, nonce })
      .map_err(|_| {
        anyhow::anyhow!("Incorrect password or corrupt export file")
      })?;

  if envelope.version == 1 {
    let v1: PayloadV1 =
      serde_json::from_slice(&plaintext).context("Corrupt export file")?;
    Ok(Payload {
      vaults: vec![VaultExport {
        name: v1.vault.name,
        description: v1.vault.description,
        environments: v1.environments,
      }],
      exported_at: 0,
    })
  } else {
    serde_json::from_slice(&plaintext).context("Corrupt export file")
  }
}

pub fn preview_import(
  envelope_json: &str,
  export_password: &str,
) -> Result<ImportPreview> {
  let payload = decrypt_payload(envelope_json, export_password)?;
  let existing_vaults = super::vault::list()?;

  let mut vaults = Vec::new();
  for vault in &payload.vaults {
    let existing = existing_vaults.iter().find(|v| v.name == vault.name);

    let existing_env_names: Vec<String> = match existing {
      Some(v) => super::environment::list(&v.id)?
        .into_iter()
        .map(|e| e.name)
        .collect(),
      None => Vec::new(),
    };

    let environments = vault
      .environments
      .iter()
      .map(|e| ImportEnvironmentPreview {
        name: e.name.clone(),
        exists: existing_env_names.contains(&e.name),
        secret_count: e.secrets.len() as i64,
      })
      .collect();

    vaults.push(ImportVaultPreview {
      name: vault.name.clone(),
      exists: existing.is_some(),
      environments,
    });
  }

  Ok(ImportPreview { vaults })
}

pub fn import_vaults(
  envelope_json: &str,
  export_password: &str,
  resolution: &ImportResolution,
) -> Result<ImportResult> {
  let payload = decrypt_payload(envelope_json, export_password)?;

  let mut vaults_imported: Vec<String> = Vec::new();
  let mut imported_count = 0i64;
  let mut skipped_count = 0i64;

  for vault in &payload.vaults {
    let Some(vres) = resolution
      .vaults
      .iter()
      .find(|r| r.source_name == vault.name)
    else {
      continue;
    };

    if vres.skip {
      skipped_count += vault
        .environments
        .iter()
        .map(|e| e.secrets.len() as i64)
        .sum::<i64>();
      continue;
    }

    let vault_id = if vres.merge_into_existing {
      super::vault::list()?
        .into_iter()
        .find(|v| v.name == vres.target_name)
        .context("Target vault no longer exists")?
        .id
    } else {
      super::vault::create(&vres.target_name, vault.description.as_deref())?
    };
    vaults_imported.push(vres.target_name.clone());

    let existing_env_names: Vec<String> = super::environment::list(&vault_id)?
      .into_iter()
      .map(|e| e.name)
      .collect();

    for env in &vault.environments {
      let Some(eres) =
        vres.environments.iter().find(|r| r.source_name == env.name)
      else {
        continue;
      };

      if eres.skip {
        skipped_count += env.secrets.len() as i64;
        continue;
      }

      let target_env = &eres.target_name;

      if !existing_env_names.contains(target_env) {
        super::environment::create(&vault_id, target_env, None)?;
      }

      let existing_keys: Vec<String> =
        super::secret::list(&vault_id, Some(target_env))?
          .into_iter()
          .map(|s| s.key)
          .collect();

      for secret in &env.secrets {
        if existing_keys.contains(&secret.key) {
          skipped_count += 1;
          continue;
        }

        super::secret::create(
          &vault_id,
          target_env,
          &secret.key,
          &secret.value,
        )?;
        imported_count += 1;
      }
    }
  }

  Ok(ImportResult {
    vaults: vaults_imported,
    imported_count,
    skipped_count,
  })
}

#[cfg(test)]
mod tests {
  use super::*;

  fn sample_payload() -> Payload {
    Payload {
      vaults: vec![
        VaultExport {
          name: "my-app".to_string(),
          description: Some("test vault".to_string()),
          environments: vec![EnvPayload {
            name: "production".to_string(),
            display_order: 0,
            secrets: vec![
              SecretPair {
                key: "API_KEY".to_string(),
                value: "super-secret".to_string(),
              },
              SecretPair {
                key: "DB_URL".to_string(),
                value: "postgres://localhost".to_string(),
              },
            ],
          }],
        },
        VaultExport {
          name: "other-app".to_string(),
          description: None,
          environments: vec![EnvPayload {
            name: "staging".to_string(),
            display_order: 0,
            secrets: vec![SecretPair {
              key: "TOKEN".to_string(),
              value: "abc123".to_string(),
            }],
          }],
        },
      ],
      exported_at: 1_750_000_000,
    }
  }

  #[test]
  fn test_seal_open_round_trip() {
    let payload = sample_payload();
    let envelope =
      seal_payload(&payload, "export-password", &Argon2Params::default())
        .unwrap();

    let opened = decrypt_payload(&envelope, "export-password").unwrap();

    assert_eq!(opened.vaults.len(), 2);
    assert_eq!(opened.vaults[0].name, "my-app");
    assert_eq!(opened.vaults[0].environments[0].secrets.len(), 2);
    assert_eq!(opened.vaults[0].environments[0].secrets[0].key, "API_KEY");
    assert_eq!(
      opened.vaults[0].environments[0].secrets[0].value,
      "super-secret"
    );
    assert_eq!(opened.vaults[1].name, "other-app");
  }

  #[test]
  fn test_open_wrong_password_fails() {
    let envelope = seal_payload(
      &sample_payload(),
      "correct-password",
      &Argon2Params::default(),
    )
    .unwrap();
    assert!(decrypt_payload(&envelope, "wrong-password").is_err());
  }

  #[test]
  fn test_open_tampered_ciphertext_fails() {
    let envelope = seal_payload(
      &sample_payload(),
      "export-password",
      &Argon2Params::default(),
    )
    .unwrap();
    let mut env: Envelope = serde_json::from_str(&envelope).unwrap();

    let mut bytes = general_purpose::STANDARD.decode(&env.ciphertext).unwrap();
    bytes[0] ^= 0xFF;
    env.ciphertext = general_purpose::STANDARD.encode(&bytes);
    let tampered = serde_json::to_string(&env).unwrap();

    assert!(decrypt_payload(&tampered, "export-password").is_err());
  }

  #[test]
  fn test_open_rejects_non_export_json() {
    assert!(decrypt_payload("{\"foo\":\"bar\"}", "pw").is_err());
  }
}
