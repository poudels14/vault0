use std::collections::HashMap;
use std::os::unix::process::CommandExt;
use std::path::Path;
use std::process::Command;

use anyhow::{anyhow, Context, Result};
use base64::Engine;
use clap::{Parser, Subcommand};
use dialoguer::{Input, MultiSelect, Password, Select};
use serde::{Deserialize, Serialize};
use tarpc::{client, context};
use tokio::net::UnixStream;
use tokio_serde::formats::Bincode;
use vault0::rpc::{
    EnvironmentInfo, ImportEnvironmentResolution, ImportPreview, ImportResolution, ImportResult,
    ImportVaultResolution, ListSecretsRequest, SecretEntry, Vault0ServiceClient, VaultInfo,
};

const BASE64: base64::engine::GeneralPurpose = base64::engine::general_purpose::STANDARD;

#[derive(Parser)]
#[command(name = "vault0")]
#[command(about = "A CLI for managing vault0 secrets", long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Load secrets from a vault into the shell environment
    Load,
    /// Unload previously loaded secrets from the shell environment
    Unload,
    /// Import secrets from a .env file
    Import {
        /// Path to the .env file to import
        file_path: String,
    },
    /// Export secrets to a .env file
    Export {
        /// Path to the .env file to export to
        file_path: String,
    },
    /// Execute a command with secrets loaded as environment variables
    ///
    /// Example: vault0 exec 'psql $DATABASE_URL' # (note the use of single quote)
    Exec {
        #[arg(trailing_var_arg = true, allow_hyphen_values = true, required = true)]
        command: Vec<String>,
    },
    /// Open a new shell with secrets loaded as environment variables
    ///
    /// Type 'exit' to return to your original shell
    Shell,
    /// Manage vaults: list, or export/import as a password-encrypted file
    Vaults {
        #[command(subcommand)]
        command: VaultsCommands,
    },
}

#[derive(Subcommand)]
enum VaultsCommands {
    /// List all vaults
    Ls,
    /// Export a vault (all environments and secrets) to an encrypted file
    Export {
        /// Path to write the encrypted export file to
        file_path: String,
    },
    /// Import a vault from an encrypted file
    Import {
        /// Path to the encrypted export file to import
        file_path: String,
    },
}

#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<()> {
    let cli = Cli::parse();
    match &cli.command {
        Commands::Load => {
            let _ = unload_secrets();
            load_secrets().await?;
        }
        Commands::Unload => {
            unload_secrets()?;
        }
        Commands::Import { file_path } => {
            import_env_file(file_path).await?;
        }
        Commands::Export { file_path } => {
            export_env_file(file_path).await?;
        }
        Commands::Exec { command } => {
            run_command(command).await?;
        }
        Commands::Shell => {
            open_shell().await?;
        }
        Commands::Vaults { command } => match command {
            VaultsCommands::Ls => {
                list_vaults().await?;
            }
            VaultsCommands::Export { file_path } => {
                export_vault_file(file_path).await?;
            }
            VaultsCommands::Import { file_path } => {
                import_vault_file(file_path).await?;
            }
        },
    }
    Ok(())
}

#[derive(Debug, Serialize, Deserialize)]
struct LoadedState {
    variables: Vec<String>,
}

struct VaultClient {
    inner: Vault0ServiceClient,
}

impl VaultClient {
    async fn connect() -> Result<Self> {
        let socket_path = format!(
            "{}/.vault0/vault0.sock",
            std::env::var("HOME").expect("HOME environment variable not set")
        );
        let stream = UnixStream::connect(&socket_path)
            .await
            .map_err(|_| anyhow!("Failed to connect. Is the vault0 app running and logged in?",))?;

        let transport = tarpc::serde_transport::new(
            tokio_util::codec::Framed::new(stream, tokio_util::codec::LengthDelimitedCodec::new()),
            Bincode::default(),
        );

        let inner = Vault0ServiceClient::new(client::Config::default(), transport).spawn();
        Ok(Self { inner })
    }

    async fn list_vaults(&self) -> Result<Vec<VaultInfo>> {
        self.inner
            .list_vaults(context::current())
            .await?
            .map_err(|e| anyhow!("Failed to list vaults: {}", e))
    }

    async fn list_environments(&self, vault_id: &str) -> Result<Vec<EnvironmentInfo>> {
        self.inner
            .list_environments(context::current(), vault_id.to_string())
            .await?
            .map_err(|e| anyhow!("Failed to list environments: {}", e))
    }

    async fn create_secret(
        &self,
        vault_id: &str,
        environment: &str,
        key: &str,
        value: &str,
    ) -> Result<()> {
        self.inner
            .create_secret(
                context::current(),
                vault_id.to_string(),
                environment.to_string(),
                key.to_string(),
                value.to_string(),
            )
            .await?
            .map_err(|e| anyhow!("Failed to create secret: {}", e))
    }

    async fn list_secrets(
        &self,
        vault_id: String,
        environment: String,
        master_password: String,
    ) -> Result<Vec<SecretEntry>> {
        self.inner
            .list_secrets(
                context::current(),
                ListSecretsRequest {
                    vault_id,
                    environment,
                    master_password,
                },
            )
            .await?
            .map_err(|e| anyhow!("{}", e))
    }

    async fn export_vaults(
        &self,
        vault_ids: Vec<String>,
        master_password: String,
        export_password: String,
    ) -> Result<String> {
        self.inner
            .export_vaults(
                context::current(),
                vault_ids,
                master_password,
                export_password,
            )
            .await?
            .map_err(|e| anyhow!("{}", e))
    }

    async fn preview_import(
        &self,
        envelope: String,
        export_password: String,
    ) -> Result<ImportPreview> {
        self.inner
            .preview_import(context::current(), envelope, export_password)
            .await?
            .map_err(|e| anyhow!("{}", e))
    }

    async fn import_vaults(
        &self,
        envelope: String,
        export_password: String,
        resolution: ImportResolution,
    ) -> Result<ImportResult> {
        self.inner
            .import_vaults(context::current(), envelope, export_password, resolution)
            .await?
            .map_err(|e| anyhow!("{}", e))
    }
}

async fn select_vault_and_env() -> Result<(VaultInfo, String)> {
    let vaults = VaultClient::connect().await?.list_vaults().await?;
    if vaults.is_empty() {
        return Err(anyhow!("No vaults found."));
    }

    let vault_names: Vec<String> = vaults.iter().map(|v| v.name.clone()).collect();
    let vault_selection = Select::new()
        .with_prompt("Select vault")
        .items(&vault_names)
        .default(0)
        .interact()?;
    let selected_vault = vaults[vault_selection].clone();

    let environments = VaultClient::connect()
        .await?
        .list_environments(&selected_vault.id)
        .await?;
    if environments.is_empty() {
        return Err(anyhow!("No environments found."));
    }

    let env_names: Vec<String> = environments.iter().map(|e| e.name.clone()).collect();
    let env_selection = Select::new()
        .with_prompt("Select environment")
        .items(&env_names)
        .default(0)
        .interact()?;

    Ok((selected_vault, env_names[env_selection].clone()))
}

async fn select_and_load_secrets() -> Result<(VaultInfo, String, Vec<SecretEntry>)> {
    let (vault, env) = select_vault_and_env().await?;
    let master_password = Password::new()
        .with_prompt("Enter master password")
        .interact()?;
    let secrets = VaultClient::connect()
        .await?
        .list_secrets(vault.id.clone(), env.clone(), master_password)
        .await?;
    Ok((vault, env, secrets))
}

async fn load_secrets() -> Result<()> {
    let (_vault, environment, secrets) = select_and_load_secrets().await?;

    if secrets.is_empty() {
        eprintln!("# No secrets found in environment '{}'", environment);
        return Ok(());
    }

    for secret in &secrets {
        println!(
            "export {}='{}'",
            secret.key,
            secret.value.replace('\'', r"'\''"),
        );
    }

    let state = LoadedState {
        variables: secrets.iter().map(|s| s.key.clone()).collect(),
    };
    let encoded = BASE64.encode(serde_json::to_string(&state)?);
    println!("export VAULT0_SHELL_STATUS={}", encoded);

    eprintln!(
        "# Loaded {} secrets (environment: '{}')",
        secrets.len(),
        environment,
    );

    Ok(())
}

async fn import_env_file(file_path: &str) -> Result<()> {
    eprintln!("Importing secrets from: {}", file_path);

    let path = Path::new(file_path);
    if !path.exists() {
        return Err(anyhow!("File not found: {}", file_path));
    }

    let env_vars: HashMap<String, String> = dotenvy::from_path_iter(path)
        .map_err(|e| anyhow!("Failed to read .env file: {}", e))?
        .filter_map(|item| item.ok())
        .collect();

    if env_vars.is_empty() {
        return Err(anyhow!("No variables found in .env file"));
    }

    eprintln!("Found {} variables", env_vars.len());

    let (selected_vault, selected_env) = select_vault_and_env().await?;

    let client = VaultClient::connect().await?;
    let mut success_count = 0;
    for (key, value) in env_vars {
        match client
            .create_secret(&selected_vault.id, &selected_env, &key, &value)
            .await
        {
            Ok(_) => success_count += 1,
            Err(e) => eprintln!("✗ Failed to import {}: {}", key, e),
        }
    }

    eprintln!(
        "\n✓ Imported {} secrets to environment '{}'",
        success_count, selected_env
    );

    Ok(())
}

fn escape_env_value(value: &str) -> String {
    let escaped = value
        .replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace('$', "\\$")
        .replace('`', "\\`");
    format!("\"{}\"", escaped)
}

async fn export_env_file(file_path: &str) -> Result<()> {
    eprintln!("Exporting secrets to: {}", file_path);

    let (_selected_vault, selected_env, secrets) = select_and_load_secrets().await?;

    if secrets.is_empty() {
        eprintln!("No secrets found in environment '{}'", selected_env);
        return Ok(());
    }

    let mut content = String::new();
    for secret in &secrets {
        content.push_str(&format!(
            "{}={}\n",
            secret.key,
            escape_env_value(&secret.value)
        ));
    }

    std::fs::write(file_path, content).context("Failed to write .env file")?;
    eprintln!("✓ Exported {} secrets to '{}'", secrets.len(), file_path);
    Ok(())
}

async fn list_vaults() -> Result<()> {
    let vaults = VaultClient::connect().await?.list_vaults().await?;
    if vaults.is_empty() {
        eprintln!("No vaults found.");
        return Ok(());
    }

    for vault in &vaults {
        match &vault.description {
            Some(desc) if !desc.is_empty() => println!("{}\t{}", vault.name, desc),
            _ => println!("{}", vault.name),
        }
    }
    Ok(())
}

async fn export_vault_file(file_path: &str) -> Result<()> {
    let vaults = VaultClient::connect().await?.list_vaults().await?;
    if vaults.is_empty() {
        return Err(anyhow!("No vaults found."));
    }

    let vault_names: Vec<String> = vaults.iter().map(|v| v.name.clone()).collect();
    let selections = MultiSelect::new()
        .with_prompt("Select vaults to export (space to toggle, enter to confirm)")
        .items(&vault_names)
        .interact()?;

    if selections.is_empty() {
        eprintln!("No vaults selected.");
        return Ok(());
    }

    let selected: Vec<&VaultInfo> = selections.iter().map(|&i| &vaults[i]).collect();
    let vault_ids: Vec<String> = selected.iter().map(|v| v.id.clone()).collect();

    let master_password = Password::new()
        .with_prompt("Enter master password")
        .interact()?;
    let export_password = Password::new()
        .with_prompt("Enter export password (used to encrypt the file)")
        .with_confirmation("Confirm export password", "Passwords don't match")
        .interact()?;

    let envelope = VaultClient::connect()
        .await?
        .export_vaults(vault_ids, master_password, export_password)
        .await?;

    std::fs::write(file_path, envelope).context("Failed to write export file")?;
    let names: Vec<&str> = selected.iter().map(|v| v.name.as_str()).collect();
    eprintln!(
        "✓ Exported {} vault(s) [{}] to '{}'",
        selected.len(),
        names.join(", "),
        file_path
    );
    Ok(())
}

async fn import_vault_file(file_path: &str) -> Result<()> {
    let path = Path::new(file_path);
    if !path.exists() {
        return Err(anyhow!("File not found: {}", file_path));
    }
    let envelope = std::fs::read_to_string(path).context("Failed to read export file")?;

    let export_password = Password::new()
        .with_prompt("Enter export password")
        .interact()?;

    let preview = VaultClient::connect()
        .await?
        .preview_import(envelope.clone(), export_password.clone())
        .await?;

    let existing_vaults = VaultClient::connect().await?.list_vaults().await?;

    let mut vault_resolutions = Vec::new();
    for vault in &preview.vaults {
        eprintln!(
            "\nVault '{}' ({} environment(s))",
            vault.name,
            vault.environments.len()
        );

        let mut target_name = vault.name.clone();
        let mut merge_into_existing = false;
        let mut skip_vault = false;
        loop {
            target_name = Input::<String>::new()
                .with_prompt("Import into vault name")
                .default(target_name.clone())
                .interact_text()?;

            match existing_vaults.iter().find(|v| v.name == target_name) {
                None => break,
                Some(existing) => {
                    let choices = vec![
                        format!("Merge into existing vault '{}'", existing.name),
                        "Choose a different name".to_string(),
                        "Skip this vault".to_string(),
                        "Cancel import".to_string(),
                    ];
                    let selection = Select::new()
                        .with_prompt(format!("Vault '{}' already exists", existing.name))
                        .items(&choices)
                        .default(0)
                        .interact()?;
                    match selection {
                        0 => {
                            merge_into_existing = true;
                            break;
                        }
                        1 => continue,
                        2 => {
                            skip_vault = true;
                            break;
                        }
                        _ => {
                            eprintln!("Cancelled.");
                            return Ok(());
                        }
                    }
                }
            }
        }

        if skip_vault {
            vault_resolutions.push(ImportVaultResolution {
                source_name: vault.name.clone(),
                target_name,
                merge_into_existing: false,
                skip: true,
                environments: Vec::new(),
            });
            continue;
        }

        let existing_env_names: Vec<String> = if merge_into_existing {
            let vault_id = existing_vaults
                .iter()
                .find(|v| v.name == target_name)
                .map(|v| v.id.clone())
                .unwrap_or_default();
            VaultClient::connect()
                .await?
                .list_environments(&vault_id)
                .await?
                .into_iter()
                .map(|e| e.name)
                .collect()
        } else {
            Vec::new()
        };

        let mut environments = Vec::new();
        for env in &vault.environments {
            let (env_target, skip) = if existing_env_names.contains(&env.name) {
                let choices = vec![
                    format!(
                        "Merge {} secret(s) into '{}' (existing keys are kept)",
                        env.secret_count, env.name
                    ),
                    "Skip this environment".to_string(),
                    "Import under a different environment name".to_string(),
                ];
                let selection = Select::new()
                    .with_prompt(format!("Environment '{}' already exists", env.name))
                    .items(&choices)
                    .default(0)
                    .interact()?;
                match selection {
                    0 => (env.name.clone(), false),
                    1 => (env.name.clone(), true),
                    _ => (
                        Input::<String>::new()
                            .with_prompt("New environment name")
                            .interact_text()?,
                        false,
                    ),
                }
            } else {
                (env.name.clone(), false)
            };

            environments.push(ImportEnvironmentResolution {
                source_name: env.name.clone(),
                target_name: env_target,
                skip,
            });
        }

        vault_resolutions.push(ImportVaultResolution {
            source_name: vault.name.clone(),
            target_name,
            merge_into_existing,
            skip: false,
            environments,
        });
    }

    let resolution = ImportResolution {
        vaults: vault_resolutions,
    };

    let result = VaultClient::connect()
        .await?
        .import_vaults(envelope, export_password, resolution)
        .await?;

    if result.vaults.is_empty() {
        eprintln!("\nNo vaults imported.");
        return Ok(());
    }

    let skipped = if result.skipped_count > 0 {
        format!(" ({} skipped)", result.skipped_count)
    } else {
        String::new()
    };
    eprintln!(
        "\n✓ Imported {} secret(s) into {} vault(s) [{}]{}",
        result.imported_count,
        result.vaults.len(),
        result.vaults.join(", "),
        skipped
    );
    Ok(())
}

fn unload_secrets() -> Result<()> {
    let encoded = match std::env::var("VAULT0_SHELL_STATUS") {
        Ok(val) => val,
        Err(_) => {
            eprintln!("# No secrets currently loaded");
            return Ok(());
        }
    };

    let decoded = BASE64
        .decode(&encoded)
        .context("Failed to decode VAULT0_SHELL_STATUS")?;
    let state: LoadedState =
        serde_json::from_slice(&decoded).context("Failed to parse VAULT0_SHELL_STATUS")?;

    for var in &state.variables {
        println!("unset '{}'", var);
    }
    println!("unset VAULT0_SHELL_STATUS");

    eprintln!("# Unloaded {} secrets", state.variables.len());
    Ok(())
}

async fn run_command(command: &[String]) -> Result<()> {
    if command.is_empty() {
        return Err(anyhow!("No command specified"));
    }

    let (selected_vault, selected_env, secrets) = select_and_load_secrets().await?;

    eprintln!(
        "Running with {} secrets from '{}/{}'",
        secrets.len(),
        selected_vault.name,
        selected_env
    );

    let mut cmd = Command::new("sh");
    cmd.arg("-c").arg(&command.join(" "));

    for secret in &secrets {
        cmd.env(&secret.key, &secret.value);
    }

    let err = cmd.exec();
    Err(anyhow!("Failed to exec: {}", err))
}

async fn open_shell() -> Result<()> {
    let (selected_vault, selected_env, secrets) = select_and_load_secrets().await?;

    let shell = std::env::var("SHELL").unwrap_or_else(|_| "/bin/sh".to_string());

    eprintln!(
        "Entering shell with {} secrets from '{}/{}' (type 'exit' to leave)",
        secrets.len(),
        selected_vault.name,
        selected_env
    );

    let mut cmd = Command::new(&shell);

    for secret in &secrets {
        cmd.env(&secret.key, &secret.value);
    }

    let err = cmd.exec();
    Err(anyhow!("Failed to exec '{}': {}", shell, err))
}
