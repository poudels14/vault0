use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::path::PathBuf;
use std::sync::{Mutex, OnceLock};

mod crypto;
mod db;
mod keychain;
mod server;
mod session;

pub mod models;
pub mod rpc;

static SERVER: OnceLock<Mutex<server::Server>> = OnceLock::new();

fn to_c_string(s: &str) -> *mut c_char {
  match CString::new(s) {
    Ok(c_str) => c_str.into_raw(),
    Err(_) => std::ptr::null_mut(),
  }
}

#[no_mangle]
pub extern "C" fn vault0_init(db_path: *const c_char) -> bool {
  let path_str = unsafe {
    match CStr::from_ptr(db_path).to_str() {
      Ok(s) => s,
      Err(e) => {
        eprintln!("Failed to convert db_path to string: {}", e);
        return false;
      }
    }
  };

  let path = PathBuf::from(path_str);
  match db::init(&path) {
    Ok(_) => true,
    Err(e) => {
      panic!("Database initialization failed: {}", e);
    }
  }
}

#[no_mangle]
pub extern "C" fn vault0_has_master_password() -> bool {
  db::auth::has_master_password()
}

#[no_mangle]
pub extern "C" fn vault0_create_master_password(
  password: *const c_char,
) -> *mut c_char {
  unsafe {
    let password_str = match CStr::from_ptr(password).to_str() {
      Ok(s) => s,
      Err(_) => return std::ptr::null_mut(),
    };

    match db::auth::create_master_password(password_str) {
      Ok(secret_key_hex) => to_c_string(&secret_key_hex),
      Err(e) => {
        eprintln!("{}", e);
        std::ptr::null_mut()
      }
    }
  }
}

#[no_mangle]
pub extern "C" fn vault0_verify_master_password(
  password: *const c_char,
  _secret_key_hex: *const c_char,
) -> bool {
  unsafe {
    let password_str = match CStr::from_ptr(password).to_str() {
      Ok(s) => s,
      Err(_) => return false,
    };

    db::auth::get_master_key(password_str)
      .and_then(|key| session::init_session(key))
      .is_ok()
  }
}

#[no_mangle]
pub extern "C" fn vault0_is_onboarding_completed() -> bool {
  db::settings::is_onboarding_completed()
}

#[no_mangle]
pub extern "C" fn vault0_set_onboarding_completed() -> bool {
  db::settings::set_onboarding_completed().is_ok()
}

#[no_mangle]
pub extern "C" fn vault0_create_vault(
  name: *const c_char,
  description: *const c_char,
) -> *mut c_char {
  unsafe {
    let name_str = match CStr::from_ptr(name).to_str() {
      Ok(s) => s,
      Err(_) => return std::ptr::null_mut(),
    };

    let desc_str = if description.is_null() {
      None
    } else {
      CStr::from_ptr(description).to_str().ok()
    };

    match db::vault::create(name_str, desc_str) {
      Ok(s) => to_c_string(&s),
      Err(e) => {
        eprintln!("{}", e);
        std::ptr::null_mut()
      }
    }
  }
}

#[no_mangle]
pub extern "C" fn vault0_list_vaults() -> *mut c_char {
  match db::vault::list() {
    Ok(vaults) => match serde_json::to_string(&vaults) {
      Ok(json) => to_c_string(&json),
      Err(_) => std::ptr::null_mut(),
    },
    Err(e) => {
      eprintln!("{}", e);
      std::ptr::null_mut()
    }
  }
}

#[no_mangle]
pub extern "C" fn vault0_update_vault(
  id: *const c_char,
  name: *const c_char,
  description: *const c_char,
) -> bool {
  unsafe {
    let id_str = match CStr::from_ptr(id).to_str() {
      Ok(s) => s,
      Err(_) => return false,
    };

    let name_str = match CStr::from_ptr(name).to_str() {
      Ok(s) => s,
      Err(_) => return false,
    };

    let desc_str = if description.is_null() {
      None
    } else {
      CStr::from_ptr(description).to_str().ok()
    };

    match db::vault::update(id_str, name_str, desc_str) {
      Ok(_) => true,
      Err(e) => {
        eprintln!("{}", e);
        false
      }
    }
  }
}

#[no_mangle]
pub extern "C" fn vault0_delete_vault(id: *const c_char) -> bool {
  unsafe {
    let id_str = match CStr::from_ptr(id).to_str() {
      Ok(s) => s,
      Err(_) => return false,
    };

    match db::vault::delete(id_str) {
      Ok(_) => true,
      Err(e) => {
        eprintln!("{}", e);
        false
      }
    }
  }
}

#[no_mangle]
pub extern "C" fn vault0_list_secrets(
  vault_id: *const c_char,
  environment: *const c_char,
) -> *mut c_char {
  unsafe {
    let vault_id_str = match CStr::from_ptr(vault_id).to_str() {
      Ok(s) => s,
      Err(_) => return std::ptr::null_mut(),
    };

    let env_str = if environment.is_null() {
      None
    } else {
      CStr::from_ptr(environment).to_str().ok()
    };

    match db::secret::list(vault_id_str, env_str) {
      Ok(secrets) => match serde_json::to_string(&secrets) {
        Ok(json) => to_c_string(&json),
        Err(_) => std::ptr::null_mut(),
      },
      Err(e) => {
        eprintln!("{}", e);
        std::ptr::null_mut()
      }
    }
  }
}

#[no_mangle]
pub extern "C" fn vault0_create_secret(
  vault_id: *const c_char,
  environment: *const c_char,
  key: *const c_char,
  value: *const c_char,
) -> bool {
  unsafe {
    let vault_id_str = match CStr::from_ptr(vault_id).to_str() {
      Ok(s) => s,
      Err(_) => return false,
    };

    let env_str = match CStr::from_ptr(environment).to_str() {
      Ok(s) => s,
      Err(_) => return false,
    };

    let key_str = match CStr::from_ptr(key).to_str() {
      Ok(s) => s,
      Err(_) => return false,
    };

    let value_str = match CStr::from_ptr(value).to_str() {
      Ok(s) => s,
      Err(_) => return false,
    };

    match db::secret::create(vault_id_str, env_str, key_str, value_str) {
      Ok(_) => true,
      Err(e) => {
        eprintln!("{}", e);
        false
      }
    }
  }
}

#[no_mangle]
pub extern "C" fn vault0_update_secret(
  id: *const c_char,
  value: *const c_char,
) -> bool {
  unsafe {
    let id_str = match CStr::from_ptr(id).to_str() {
      Ok(s) => s,
      Err(_) => return false,
    };

    let value_str = match CStr::from_ptr(value).to_str() {
      Ok(s) => s,
      Err(_) => return false,
    };

    match db::secret::update(id_str, value_str) {
      Ok(_) => true,
      Err(e) => {
        eprintln!("{}", e);
        false
      }
    }
  }
}

#[no_mangle]
pub extern "C" fn vault0_delete_secret(id: *const c_char) -> bool {
  unsafe {
    let id_str = match CStr::from_ptr(id).to_str() {
      Ok(s) => s,
      Err(_) => return false,
    };

    match db::secret::delete(id_str) {
      Ok(_) => true,
      Err(e) => {
        eprintln!("{}", e);
        false
      }
    }
  }
}

#[no_mangle]
pub extern "C" fn vault0_clear_session() {
  session::clear_session();
}

#[no_mangle]
pub extern "C" fn vault0_list_environments(
  vault_id: *const c_char,
) -> *mut c_char {
  unsafe {
    let vault_id_str = match CStr::from_ptr(vault_id).to_str() {
      Ok(s) => s,
      Err(_) => return std::ptr::null_mut(),
    };

    match db::environment::list(vault_id_str) {
      Ok(environments) => match serde_json::to_string(&environments) {
        Ok(json) => to_c_string(&json),
        Err(_) => std::ptr::null_mut(),
      },
      Err(e) => {
        eprintln!("{}", e);
        std::ptr::null_mut()
      }
    }
  }
}

#[no_mangle]
pub extern "C" fn vault0_create_environment(
  vault_id: *const c_char,
  name: *const c_char,
) -> bool {
  unsafe {
    let vault_id_str = match CStr::from_ptr(vault_id).to_str() {
      Ok(s) => s,
      Err(_) => return false,
    };

    let name_str = match CStr::from_ptr(name).to_str() {
      Ok(s) => s,
      Err(_) => return false,
    };

    match db::environment::create(vault_id_str, name_str) {
      Ok(_) => true,
      Err(e) => {
        eprintln!("{}", e);
        false
      }
    }
  }
}

#[no_mangle]
pub extern "C" fn vault0_delete_environment(
  vault_id: *const c_char,
  name: *const c_char,
) -> bool {
  unsafe {
    let vault_id_str = match CStr::from_ptr(vault_id).to_str() {
      Ok(s) => s,
      Err(_) => return false,
    };

    let name_str = match CStr::from_ptr(name).to_str() {
      Ok(s) => s,
      Err(_) => return false,
    };

    match db::environment::delete(vault_id_str, name_str) {
      Ok(_) => true,
      Err(e) => {
        eprintln!("{}", e);
        false
      }
    }
  }
}

#[no_mangle]
pub extern "C" fn vault0_free_string(s: *mut c_char) {
  unsafe {
    if !s.is_null() {
      let _ = CString::from_raw(s);
    }
  }
}

#[no_mangle]
pub extern "C" fn vault0_server_start() -> bool {
  SERVER.get_or_init(|| Mutex::new(server::Server::new()));

  let server = SERVER.get().expect("Server not initialized");
  let mut server_guard = server.lock().unwrap();

  match server_guard.start() {
    Ok(_) => {
      log::info!("Socket server started");
      true
    }
    Err(e) => {
      eprintln!("Failed to start server: {}", e);
      false
    }
  }
}

#[no_mangle]
pub extern "C" fn vault0_server_stop() {
  if let Some(server) = SERVER.get() {
    let mut server_guard = server.lock().unwrap();
    server_guard.stop();
    log::info!("Socket server stopped");
  }
}

#[no_mangle]
pub extern "C" fn vault0_create_api_key(
  name: *const c_char,
  vault_id: *const c_char,
  environment: *const c_char,
  expiration_days: i32,
) -> *mut c_char {
  unsafe {
    let name_str = match CStr::from_ptr(name).to_str() {
      Ok(s) => s,
      Err(_) => return std::ptr::null_mut(),
    };

    let vault_id_str = match CStr::from_ptr(vault_id).to_str() {
      Ok(s) => s,
      Err(_) => return std::ptr::null_mut(),
    };

    let env_str = match CStr::from_ptr(environment).to_str() {
      Ok(s) => s,
      Err(_) => return std::ptr::null_mut(),
    };

    let expiration = if expiration_days < 0 {
      None
    } else {
      Some(expiration_days)
    };

    let request = models::CreateApiKeyRequest {
      name: name_str.to_string(),
      vault_id: vault_id_str.to_string(),
      environment: env_str.to_string(),
      expiration_days: expiration,
    };

    match db::api_key::create(&request) {
      Ok(response) => match serde_json::to_string(&response) {
        Ok(json) => to_c_string(&json),
        Err(_) => std::ptr::null_mut(),
      },
      Err(e) => {
        eprintln!("{}", e);
        std::ptr::null_mut()
      }
    }
  }
}

#[no_mangle]
pub extern "C" fn vault0_list_api_keys(vault_id: *const c_char) -> *mut c_char {
  unsafe {
    let vault_id_opt = if vault_id.is_null() {
      None
    } else {
      match CStr::from_ptr(vault_id).to_str() {
        Ok(s) => Some(s.to_string()),
        Err(_) => return std::ptr::null_mut(),
      }
    };

    match db::api_key::list(vault_id_opt) {
      Ok(api_keys) => match serde_json::to_string(&api_keys) {
        Ok(json) => to_c_string(&json),
        Err(_) => std::ptr::null_mut(),
      },
      Err(e) => {
        eprintln!("{}", e);
        std::ptr::null_mut()
      }
    }
  }
}

#[no_mangle]
pub extern "C" fn vault0_delete_api_key(api_key_id: *const c_char) -> bool {
  unsafe {
    let id_str = match CStr::from_ptr(api_key_id).to_str() {
      Ok(s) => s,
      Err(_) => return false,
    };

    match db::api_key::delete(id_str) {
      Ok(_) => true,
      Err(e) => {
        eprintln!("{}", e);
        false
      }
    }
  }
}

#[no_mangle]
pub extern "C" fn vault0_cleanup_expired_api_keys() -> i32 {
  match db::api_key::cleanup_expired() {
    Ok(count) => count as i32,
    Err(e) => {
      eprintln!("{}", e);
      -1
    }
  }
}
