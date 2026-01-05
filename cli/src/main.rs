use std::collections::HashMap;
use std::os::unix::process::CommandExt;
use std::path::Path;
use std::process::Command;

use aes_gcm::{
    aead::{Aead, KeyInit},
    Aes256Gcm, Nonce,
};
use anyhow::{anyhow, bail, Context, Result};
use base64::Engine;
use clap::{Parser, Subcommand};
use dialoguer::{Password, Select};
use serde::{Deserialize, Serialize};
use tarpc::{client, context};
use tokio::net::UnixStream;
use tokio_serde::formats::Bincode;
use vault0::{
    models::ApiSecretPayload,
    rpc::{EnvironmentInfo, ListSecretsRequest, SecretEntry, Vault0ServiceClient, VaultInfo},
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
}

fn decrypt_secret(dek: &[u8; 32], ciphertext: &[u8], nonce: &[u8]) -> Result<String> {
    let cipher =
        Aes256Gcm::new_from_slice(dek).map_err(|e| anyhow!("Failed to create cipher: {}", e))?;

    let nonce_array: [u8; 12] = nonce
        .try_into()
        .map_err(|_| anyhow!("Invalid nonce length"))?;

    let plaintext = cipher
        .decrypt(Nonce::from_slice(&nonce_array), ciphertext)
        .map_err(|e| anyhow!("Decryption failed: {}", e))?;

    String::from_utf8(plaintext).context("Decrypted data is not valid UTF-8")
}

async fn load_secrets() -> Result<()> {
    let api_key = std::env::var("VAULT0_API_KEY").context("VAULT0_API_KEY is not set")?;
    let api_secret_b64 =
        std::env::var("VAULT0_API_SECRET").context("VAULT0_API_SECRET is not set")?;

    let api_secret_json = BASE64
        .decode(&api_secret_b64)
        .context("Invalid VAULT0_API_SECRET")?;
    let api_secret: ApiSecretPayload =
        serde_json::from_slice(&api_secret_json).context("Invalid VAULT0_API_SECRET")?;

    let dek_bytes = BASE64
        .decode(&api_secret.dek)
        .context("Invalid VAULT0_API_SECRET")?;
    if dek_bytes.len() != 32 {
        bail!("Invalid VAULT0_API_SECRET");
    }
    let mut dek: [u8; 32] = [0u8; 32];
    dek.copy_from_slice(&dek_bytes);

    let client = VaultClient::connect().await?;
    let result = client
        .inner
        .load_with_api_key(context::current(), api_key)
        .await?
        .map_err(|e| anyhow!("Failed to load secrets: {}", e))?;

    if result.api_key_id != api_secret.api_key_id {
        bail!("VAULT0_API_KEY and VAULT0_API_SECRET are not for the same API key");
    }

    if result.secrets.is_empty() {
        eprintln!(
            "# No secrets found for '{}' (vault: '{}', environment: '{}')",
            result.name, result.vault_id, result.environment
        );
        return Ok(());
    }

    let mut decrypted_secrets: Vec<(String, String)> = Vec::new();
    for secret in &result.secrets {
        let key = decrypt_secret(&dek, &secret.encrypted_key, &secret.key_nonce)?;
        let value = decrypt_secret(&dek, &secret.encrypted_value, &secret.value_nonce)?;
        decrypted_secrets.push((key, value));
    }

    let variable_names: Vec<String> = decrypted_secrets.iter().map(|(k, _)| k.clone()).collect();

    for (key, value) in &decrypted_secrets {
        println!("export {}='{}'", key, value.replace('\'', r"'\''"));
    }

    let state = LoadedState {
        variables: variable_names,
    };

    let encoded = BASE64.encode(serde_json::to_string(&state)?);
    println!("export VAULT0_SHELL_STATUS={}", encoded);

    eprintln!(
        "# Loaded {} secrets (environment: '{}')",
        decrypted_secrets.len(),
        result.environment
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

    let vaults = VaultClient::connect().await?.list_vaults().await?;
    if vaults.is_empty() {
        return Err(anyhow!("No vaults found. Please create a vault first."));
    }

    let vault_names: Vec<String> = vaults.iter().map(|v| v.name.clone()).collect();
    let vault_selection = Select::new()
        .with_prompt("Select vault")
        .items(&vault_names)
        .interact()?;

    let selected_vault = &vaults[vault_selection];

    let environments = VaultClient::connect()
        .await?
        .list_environments(&selected_vault.id)
        .await?;
    if environments.is_empty() {
        return Err(anyhow!(
            "No environments found. Please create an environment first."
        ));
    }

    let env_names: Vec<String> = environments.iter().map(|e| e.name.clone()).collect();
    let env_selection = Select::new()
        .with_prompt("Select environment")
        .items(&env_names)
        .interact()?;

    let client = VaultClient::connect().await?;
    let selected_env = &env_names[env_selection];
    let mut success_count = 0;
    for (key, value) in env_vars {
        match client
            .create_secret(&selected_vault.id, selected_env, &key, &value)
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

async fn export_env_file(file_path: &str) -> Result<()> {
    eprintln!("Exporting secrets to: {}", file_path);

    let vaults = VaultClient::connect().await?.list_vaults().await?;
    if vaults.is_empty() {
        return Err(anyhow!("No vaults found."));
    }

    let vault_names: Vec<String> = vaults.iter().map(|v| v.name.clone()).collect();
    let vault_selection = Select::new()
        .with_prompt("Select vault")
        .items(&vault_names)
        .interact()?;

    let selected_vault = &vaults[vault_selection];

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
        .interact()?;

    let selected_env = &env_names[env_selection];

    let master_password = Password::new()
        .with_prompt("Enter master password")
        .interact()?;

    let client = VaultClient::connect().await?;
    let secrets = client
        .list_secrets(
            selected_vault.id.clone(),
            selected_env.clone(),
            master_password.clone(),
        )
        .await?;

    if secrets.is_empty() {
        eprintln!("No secrets found in environment '{}'", selected_env);
        return Ok(());
    }

    let mut content = String::new();
    for secret in &secrets {
        content.push_str(&format!("{}={}\n", secret.key, secret.value));
    }

    std::fs::write(file_path, content).context("Failed to write .env file")?;
    eprintln!("✓ Exported {} secrets to '{}'", secrets.len(), file_path);
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

    let vaults = VaultClient::connect().await?.list_vaults().await?;
    if vaults.is_empty() {
        return Err(anyhow!("No vaults found."));
    }

    let vault_names: Vec<String> = vaults.iter().map(|v| v.name.clone()).collect();
    let vault_selection = Select::new()
        .with_prompt("Select vault")
        .items(&vault_names)
        .interact()?;

    let selected_vault = &vaults[vault_selection];

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
        .interact()?;

    let selected_env = &env_names[env_selection];

    let master_password = Password::new()
        .with_prompt("Enter master password")
        .interact()?;

    let client = VaultClient::connect().await?;
    let secrets = client
        .list_secrets(
            selected_vault.id.clone(),
            selected_env.clone(),
            master_password,
        )
        .await?;

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
    let vaults = VaultClient::connect().await?.list_vaults().await?;
    if vaults.is_empty() {
        return Err(anyhow!("No vaults found."));
    }

    let vault_names: Vec<String> = vaults.iter().map(|v| v.name.clone()).collect();
    let vault_selection = Select::new()
        .with_prompt("Select vault")
        .items(&vault_names)
        .interact()?;

    let selected_vault = &vaults[vault_selection];

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
        .interact()?;

    let selected_env = &env_names[env_selection];

    let master_password = Password::new()
        .with_prompt("Enter master password")
        .interact()?;

    let client = VaultClient::connect().await?;
    let secrets = client
        .list_secrets(
            selected_vault.id.clone(),
            selected_env.clone(),
            master_password,
        )
        .await?;

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
