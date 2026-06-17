use anyhow::Result;
use diesel::prelude::*;
use diesel::sql_query;
use diesel::sql_types::{BigInt, Text};

#[derive(QueryableByName)]
struct SettingRow {
  #[diesel(sql_type = Text)]
  value: String,
}

pub fn is_onboarding_completed() -> bool {
  let mut conn = match super::conn() {
    Ok(c) => c,
    Err(_) => return false,
  };

  let result: Result<Vec<SettingRow>, _> = sql_query(
    "SELECT value FROM app_settings WHERE key = 'onboarding_completed'",
  )
  .load(&mut conn);

  match result {
    Ok(rows) => rows.first().map(|r| r.value == "true").unwrap_or(false),
    Err(_) => false,
  }
}

pub fn set_onboarding_completed() -> Result<()> {
  let mut conn = super::conn()?;
  let now = chrono::Utc::now().timestamp();

  sql_query(
    "INSERT OR REPLACE INTO app_settings (key, value, updated_at) VALUES ('onboarding_completed', 'true', ?)",
  )
  .bind::<BigInt, _>(now)
  .execute(&mut conn)?;

  Ok(())
}

/// Path to the 1Password `op` CLI. Defaults to `"op"` (resolved via PATH) when
/// not configured.
pub fn get_op_cli_path() -> String {
  let mut conn = match super::conn() {
    Ok(c) => c,
    Err(_) => return "op".to_string(),
  };

  let result: Result<Vec<SettingRow>, _> =
    sql_query("SELECT value FROM app_settings WHERE key = 'op_cli_path'")
      .load(&mut conn);

  match result {
    Ok(rows) => rows
      .first()
      .map(|r| r.value.clone())
      .filter(|v| !v.trim().is_empty())
      .unwrap_or_else(|| "op".to_string()),
    Err(_) => "op".to_string(),
  }
}

pub fn set_op_cli_path(path: &str) -> Result<()> {
  let mut conn = super::conn()?;
  let now = chrono::Utc::now().timestamp();

  sql_query(
    "INSERT OR REPLACE INTO app_settings (key, value, updated_at) VALUES ('op_cli_path', ?, ?)",
  )
  .bind::<Text, _>(path)
  .bind::<BigInt, _>(now)
  .execute(&mut conn)?;

  Ok(())
}
