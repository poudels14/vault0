pub mod api_key;
pub mod auth;
pub mod environment;
pub mod secret;
pub mod settings;
pub mod vault;
pub mod vault_key;

use std::path::PathBuf;
use std::sync::OnceLock;

use anyhow::{Context, Result};
use diesel::prelude::*;
use diesel::r2d2::{ConnectionManager, Pool};
use diesel::sql_query;
use diesel::sql_types::Integer;

pub type DbPool = Pool<ConnectionManager<SqliteConnection>>;

static DB_POOL: OnceLock<DbPool> = OnceLock::new();

pub fn init(db_path: &PathBuf) -> Result<()> {
  if DB_POOL.get().is_some() {
    return Ok(());
  }

  if let Some(parent) = db_path.parent() {
    std::fs::create_dir_all(parent)?;
  }

  let db_url = if db_path.to_string_lossy() == ":memory:" {
    ":memory:".to_string()
  } else {
    db_path.to_string_lossy().to_string()
  };

  let manager = ConnectionManager::<SqliteConnection>::new(&db_url);
  let pool = Pool::builder()
    .max_size(5)
    .build(manager)
    .context("Failed to create connection pool")?;

  run_migrations(&pool)?;

  let _ = DB_POOL.set(pool);
  Ok(())
}

pub fn pool() -> &'static DbPool {
  DB_POOL
    .get()
    .expect("Database not initialized. Call db::init first.")
}

pub fn conn(
) -> Result<diesel::r2d2::PooledConnection<ConnectionManager<SqliteConnection>>>
{
  pool().get().context("Failed to get database connection")
}

fn run_migrations(pool: &DbPool) -> Result<()> {
  let mut conn = pool.get().context("Failed to get connection")?;

  sql_query(
    "CREATE TABLE IF NOT EXISTS schema_migrations (
      version INTEGER PRIMARY KEY,
      applied_at INTEGER NOT NULL
    )",
  )
  .execute(&mut conn)?;

  let migrations =
    [(1, include_str!("../../migrations/001_initial_schema.sql"))];

  for (version, migration_sql) in migrations {
    #[derive(QueryableByName)]
    struct ExistsResult {
      #[diesel(sql_type = Integer)]
      exists_flag: i32,
    }

    let result: Vec<ExistsResult> = sql_query(
      "SELECT EXISTS(SELECT 1 FROM schema_migrations WHERE version = ?) as exists_flag",
    )
    .bind::<Integer, _>(version)
    .load(&mut conn)?;

    let already_applied =
      result.first().map(|r| r.exists_flag != 0).unwrap_or(false);

    if !already_applied {
      log::info!("Running migration {}", version);

      for statement in migration_sql.split(';') {
        let statement = statement.trim();
        if !statement.is_empty() {
          sql_query(statement).execute(&mut conn)?;
        }
      }

      sql_query(
        "INSERT INTO schema_migrations (version, applied_at) VALUES (?, strftime('%s', 'now'))",
      )
      .bind::<Integer, _>(version)
      .execute(&mut conn)?;

      log::info!("Migration {} completed", version);
    }
  }

  Ok(())
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn test_init_db() {
    init(&PathBuf::from(":memory:")).unwrap();

    let mut conn = conn().unwrap();

    #[derive(QueryableByName)]
    struct TableName {
      #[diesel(sql_type = diesel::sql_types::Text)]
      name: String,
    }

    let rows: Vec<TableName> =
      sql_query("SELECT name FROM sqlite_master WHERE type='table'")
        .load(&mut conn)
        .unwrap();

    let tables: Vec<String> = rows.into_iter().map(|r| r.name).collect();

    assert!(tables.contains(&"vaults".to_string()));
    assert!(tables.contains(&"secrets".to_string()));
    assert!(tables.contains(&"master_passwords".to_string()));
    assert!(tables.contains(&"app_settings".to_string()));
  }
}
