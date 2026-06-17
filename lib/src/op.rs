use std::process::Command;

use anyhow::{bail, Context, Result};
use serde::{Deserialize, Serialize};

use crate::db::settings;

/// A 1Password vault or item, as surfaced to the UI pickers.
#[derive(Debug, Serialize, Deserialize)]
pub struct OpEntry {
  pub id: String,
  pub name: String,
}

#[derive(Deserialize)]
struct RawVault {
  id: String,
  name: String,
}

#[derive(Deserialize)]
struct RawItem {
  id: String,
  title: String,
}

#[derive(Deserialize)]
struct RawField {
  #[serde(default)]
  label: Option<String>,
  #[serde(default)]
  value: Option<String>,
}

#[derive(Deserialize)]
struct RawItemDetail {
  #[serde(default)]
  fields: Vec<RawField>,
}

/// Runs the `op` CLI with the given args, authenticating with the provided
/// service account token (passed via env, never argv). Returns stdout bytes.
fn run(token: &str, args: &[&str]) -> Result<Vec<u8>> {
  let op = settings::get_op_cli_path();

  let output = Command::new(&op)
    .args(args)
    .env("OP_SERVICE_ACCOUNT_TOKEN", token)
    .output()
    .map_err(|e| {
      anyhow::anyhow!(
        "Could not run the 1Password CLI ('{}'): {}. Install it or set the op CLI path.",
        op,
        e
      )
    })?;

  if !output.status.success() {
    let stderr = String::from_utf8_lossy(&output.stderr);
    bail!("op command failed: {}", stderr.trim());
  }

  Ok(output.stdout)
}

/// Verifies the `op` CLI is present and runnable.
pub fn ensure_available() -> Result<()> {
  let op = settings::get_op_cli_path();
  Command::new(&op).arg("--version").output().map_err(|e| {
    anyhow::anyhow!(
      "1Password CLI not found ('{}'): {}. Install it or configure the op CLI path.",
      op,
      e
    )
  })?;
  Ok(())
}

pub fn list_vaults(token: &str) -> Result<Vec<OpEntry>> {
  let stdout = run(token, &["vault", "list", "--format", "json"])?;
  let raw: Vec<RawVault> =
    serde_json::from_slice(&stdout).context("Failed to parse op vault list")?;
  Ok(
    raw
      .into_iter()
      .map(|v| OpEntry {
        id: v.id,
        name: v.name,
      })
      .collect(),
  )
}

pub fn list_items(token: &str, vault: &str) -> Result<Vec<OpEntry>> {
  let stdout = run(
    token,
    &["item", "list", "--vault", vault, "--format", "json"],
  )?;
  let raw: Vec<RawItem> =
    serde_json::from_slice(&stdout).context("Failed to parse op item list")?;
  Ok(
    raw
      .into_iter()
      .map(|i| OpEntry {
        id: i.id,
        name: i.title,
      })
      .collect(),
  )
}

/// Reads all non-empty labeled fields of an item as (key, value) pairs.
pub fn get_fields(
  token: &str,
  vault: &str,
  item: &str,
) -> Result<Vec<(String, String)>> {
  let stdout = run(
    token,
    &[
      "item", "get", item, "--vault", vault, "--format", "json", "--reveal",
    ],
  )?;
  let detail: RawItemDetail =
    serde_json::from_slice(&stdout).context("Failed to parse op item")?;

  Ok(
    detail
      .fields
      .into_iter()
      .filter_map(|f| match (f.label, f.value) {
        (Some(label), Some(value))
          if !label.is_empty() && !value.is_empty() =>
        {
          Some((label, value))
        }
        _ => None,
      })
      .collect(),
  )
}

/// Sets (creates or updates) a concealed field on an item.
pub fn set_field(
  token: &str,
  vault: &str,
  item: &str,
  key: &str,
  value: &str,
) -> Result<()> {
  let assignment = format!("{}[password]={}", key, value);
  run(
    token,
    &["item", "edit", item, "--vault", vault, &assignment],
  )?;
  Ok(())
}

/// Removes a field from an item.
pub fn delete_field(
  token: &str,
  vault: &str,
  item: &str,
  key: &str,
) -> Result<()> {
  let assignment = format!("{}[delete]=", key);
  run(
    token,
    &["item", "edit", item, "--vault", vault, &assignment],
  )?;
  Ok(())
}
