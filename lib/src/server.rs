use anyhow::{bail, Context, Result};
use futures::{future, prelude::*};
use tarpc::server::{self, Channel};
use tokio::net::UnixListener;
use tokio::runtime::Runtime;
use tokio::sync::oneshot;
use tokio_serde::formats::Bincode;

use crate::rpc::{
  ApiKeyLoadResponse, EncryptedSecretEntry, EnvironmentInfo, Vault0Service,
  VaultInfo,
};
use crate::{db, session};

#[derive(Clone)]
struct Vault0Server;

impl Vault0Service for Vault0Server {
  async fn list_vaults(
    self,
    _: tarpc::context::Context,
  ) -> Result<Vec<VaultInfo>, String> {
    if session::get_master_key().is_err() {
      return Err("Not authenticated".to_string());
    }

    tokio::task::spawn_blocking(|| {
      db::vault::list()
        .map(|vaults| {
          vaults
            .into_iter()
            .map(|v| VaultInfo {
              id: v.id,
              name: v.name,
              description: v.description,
            })
            .collect()
        })
        .map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| e.to_string())?
  }

  async fn list_environments(
    self,
    _: tarpc::context::Context,
    vault_id: String,
  ) -> Result<Vec<EnvironmentInfo>, String> {
    if session::get_master_key().is_err() {
      return Err("Not authenticated".to_string());
    }

    tokio::task::spawn_blocking(move || {
      db::environment::list(&vault_id)
        .map(|envs| {
          envs
            .into_iter()
            .map(|e| EnvironmentInfo {
              id: e.id,
              name: e.name,
              display_order: e.display_order,
            })
            .collect()
        })
        .map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| e.to_string())?
  }

  async fn create_secret(
    self,
    _: tarpc::context::Context,
    vault_id: String,
    environment: String,
    key: String,
    value: String,
  ) -> Result<(), String> {
    if session::get_master_key().is_err() {
      return Err("Not authenticated".to_string());
    }

    tokio::task::spawn_blocking(move || {
      db::secret::create(&vault_id, &environment, &key, &value)
        .map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| e.to_string())?
  }

  async fn load_with_api_key(
    self,
    _: tarpc::context::Context,
    api_key: String,
  ) -> Result<ApiKeyLoadResponse, String> {
    tokio::task::spawn_blocking(move || {
      let claims = db::api_key::verify_and_decode_jwt(&api_key)
        .map_err(|e| format!("JWT verification failed: {}", e))?;

      let encrypted_secrets =
        db::api_key::get_encrypted_secrets(&claims.api_key_id)
          .map_err(|e| format!("Failed to load secrets: {}", e))?;

      if let Err(e) = db::api_key::update_last_used(&claims.api_key_id) {
        log::warn!("Failed to update last_used_at: {}", e);
      }

      Ok(ApiKeyLoadResponse {
        api_key_id: claims.api_key_id,
        vault_id: claims.vault_id,
        environment: claims.environment,
        name: claims.name,
        secrets: encrypted_secrets
          .into_iter()
          .map(|s| EncryptedSecretEntry {
            encrypted_key: s.encrypted_key,
            key_nonce: s.key_nonce,
            encrypted_value: s.encrypted_value,
            value_nonce: s.value_nonce,
          })
          .collect(),
      })
    })
    .await
    .map_err(|e| e.to_string())?
  }

  async fn list_secrets(
    self,
    _: tarpc::context::Context,
    request: crate::rpc::ListSecretsRequest,
  ) -> Result<Vec<crate::rpc::SecretEntry>, String> {
    if session::get_master_key().is_err() {
      return Err(
        "Session not active. Please unlock the app first.".to_string(),
      );
    }

    tokio::task::spawn_blocking(move || {
      db::auth::verify_password(&request.master_password)
        .map_err(|e| format!("Password verification failed: {}", e))?;

      db::secret::list(&request.vault_id, Some(&request.environment))
        .map(|secrets| {
          secrets
            .into_iter()
            .map(|s| crate::rpc::SecretEntry {
              key: s.key,
              value: s.value,
            })
            .collect()
        })
        .map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| e.to_string())?
  }
}

async fn spawn_server(
  listener: UnixListener,
  shutdown_rx: oneshot::Receiver<()>,
) {
  let codec_builder = Bincode::default;

  futures::pin_mut!(shutdown_rx);

  loop {
    let accept = listener.accept();
    futures::pin_mut!(accept);

    match future::select(accept, &mut shutdown_rx).await {
      future::Either::Left((result, _)) => match result {
        Ok((stream, _addr)) => {
          let transport = tarpc::serde_transport::new(
            tokio_util::codec::Framed::new(
              stream,
              tokio_util::codec::LengthDelimitedCodec::new(),
            ),
            codec_builder(),
          );

          let server = server::BaseChannel::with_defaults(transport);
          tokio::spawn(server.execute(Vault0Server.serve()).for_each(
            |response| async move {
              tokio::spawn(response);
            },
          ));
        }
        Err(e) => {
          log::error!("Accept error: {}", e);
        }
      },
      future::Either::Right(_) => {
        log::info!("Server shutting down");
        break;
      }
    }
  }
}

pub struct Server {
  runtime: Option<Runtime>,
  shutdown_tx: Option<oneshot::Sender<()>>,
}

impl Server {
  pub fn new() -> Self {
    Server {
      runtime: None,
      shutdown_tx: None,
    }
  }

  pub fn start(&mut self) -> Result<()> {
    let socket_path =
      format!("{}/.vault0/vault0.sock", std::env::var("HOME").unwrap());

    if std::path::Path::new(&socket_path).exists() {
      if let Ok(_stream) = std::os::unix::net::UnixStream::connect(&socket_path)
      {
        bail!("Server is already running");
      } else {
        log::info!("Removing stale socket file at {}", socket_path);
        if let Err(e) = std::fs::remove_file(&socket_path) {
          log::warn!("Failed to remove stale socket: {}", e);
        }
      }
    }

    let runtime = tokio::runtime::Builder::new_multi_thread()
      .enable_all()
      .build()
      .context("Failed to create runtime")?;

    let (shutdown_tx, shutdown_rx) = oneshot::channel();

    let socket_path_clone = socket_path.clone();
    runtime.handle().spawn(async move {
      let listener = match UnixListener::bind(&socket_path_clone) {
        Ok(l) => {
          log::info!("Socket server listening at {}", socket_path_clone);
          l
        }
        Err(e) => {
          eprintln!("Failed to bind socket: {}", e);
          return;
        }
      };

      spawn_server(listener, shutdown_rx).await;

      let _ = std::fs::remove_file(&socket_path_clone);
    });

    self.runtime = Some(runtime);
    self.shutdown_tx = Some(shutdown_tx);

    Ok(())
  }

  pub fn stop(&mut self) {
    if let Some(tx) = self.shutdown_tx.take() {
      let _ = tx.send(());
    }
    self.runtime = None;
  }
}

impl Drop for Server {
  fn drop(&mut self) {
    self.stop();
  }
}
