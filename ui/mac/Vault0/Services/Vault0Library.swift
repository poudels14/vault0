//  Swift wrapper around Rust FFI library

import Foundation

class Vault0Library {
    static let shared = Vault0Library()

    private init() {
        let dbPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".vault0/vault0.db").path

        let success = dbPath.withCString { vault0_init($0) }
        if success {
            NSLog("Vault0 library initialized successfully")
        } else {
            fatalError("Failed to initialize Vault0 library")
        }
    }

    func hasMasterPassword() -> Bool {
        vault0_has_master_password()
    }

    func createMasterPassword(_ password: String) -> Bool {
        guard let secretKeyPtr = password.withCString({ vault0_create_master_password($0) }) else {
            NSLog("Failed to create master password")
            return false
        }

        defer { vault0_free_string(secretKeyPtr) }
        return true
    }

    func verifyMasterPassword(_ password: String) -> Bool {
        let result = password.withCString { passwordPtr in
            vault0_verify_master_password(passwordPtr, nil)
        }
        NSLog(result ? "Master password verification succeeded" : "Master password verification failed")
        return result
    }

    func clearSession() {
        vault0_clear_session()
    }

    func isOnboardingCompleted() -> Bool {
        vault0_is_onboarding_completed()
    }

    func setOnboardingCompleted() -> Bool {
        vault0_set_onboarding_completed()
    }

    func createVault(name: String, description: String?) -> String? {
        let resultPtr = name.withCString { namePtr in
            if let desc = description {
                desc.withCString { descPtr in
                    vault0_create_vault(namePtr, descPtr)
                }
            } else {
                vault0_create_vault(namePtr, nil)
            }
        }

        guard let ptr = resultPtr else {
            return nil
        }

        defer { vault0_free_string(ptr) }
        return String(cString: ptr)
    }

    func listVaults() -> [Vault] {
        guard let jsonPtr = vault0_list_vaults() else {
            NSLog("vault0_list_vaults returned null")
            return []
        }

        defer { vault0_free_string(jsonPtr) }

        let jsonString = String(cString: jsonPtr)
        guard let data = jsonString.data(using: .utf8) else {
            NSLog("Failed to convert JSON string to data")
            return []
        }

        do {
            let vaults = try JSONDecoder().decode([Vault].self, from: data)
            NSLog("Loaded \(vaults.count) vaults")
            return vaults
        } catch {
            NSLog("Failed to decode vaults: \(error)")
            return []
        }
    }

    func updateVault(id: String, name: String, description: String?) -> Bool {
        id.withCString { idPtr in
            name.withCString { namePtr in
                if let desc = description {
                    desc.withCString { descPtr in
                        vault0_update_vault(idPtr, namePtr, descPtr)
                    }
                } else {
                    vault0_update_vault(idPtr, namePtr, nil)
                }
            }
        }
    }

    func deleteVault(id: String) -> Bool {
        id.withCString { vault0_delete_vault($0) }
    }

    func listSecrets(vaultId: String, environment: String?) -> [Secret] {
        let jsonPtr: UnsafeMutablePointer<CChar>? = vaultId.withCString { vaultIdPtr in
            if let env = environment {
                env.withCString { envPtr in
                    vault0_list_secrets(vaultIdPtr, envPtr)
                }
            } else {
                vault0_list_secrets(vaultIdPtr, nil)
            }
        }

        guard let ptr = jsonPtr else {
            NSLog("vault0_list_secrets returned null")
            return []
        }

        defer { vault0_free_string(ptr) }

        let jsonString = String(cString: ptr)
        guard let data = jsonString.data(using: .utf8) else {
            NSLog("Failed to convert JSON string to data")
            return []
        }

        do {
            let secrets = try JSONDecoder().decode([Secret].self, from: data)
            NSLog("Loaded \(secrets.count) secrets for vault \(vaultId)")
            return secrets
        } catch {
            NSLog("Failed to decode secrets: \(error)")
            return []
        }
    }

    func createSecret(vaultId: String, environment: String, key: String, value: String) -> Bool {
        vaultId.withCString { vaultIdPtr in
            environment.withCString { envPtr in
                key.withCString { keyPtr in
                    value.withCString { valPtr in
                        vault0_create_secret(vaultIdPtr, envPtr, keyPtr, valPtr)
                    }
                }
            }
        }
    }

    func updateSecret(id: String, value: String) -> Bool {
        id.withCString { idPtr in
            value.withCString { valuePtr in
                vault0_update_secret(idPtr, valuePtr)
            }
        }
    }

    func deleteSecret(id: String) -> Bool {
        id.withCString { vault0_delete_secret($0) }
    }

    func listEnvironments(vaultId: String) -> [String] {
        let jsonPtr = vaultId.withCString { vault0_list_environments($0) }
        guard let jsonPtr else {
            NSLog("vault0_list_environments returned null")
            return []
        }

        defer { vault0_free_string(jsonPtr) }

        let jsonString = String(cString: jsonPtr)
        guard let data = jsonString.data(using: .utf8) else {
            NSLog("Failed to convert JSON string to data")
            return []
        }

        do {
            let environments = try JSONDecoder().decode([EnvironmentItem].self, from: data)
            NSLog("Loaded \(environments.count) environments for vault \(vaultId)")
            return environments.map(\.name)
        } catch {
            NSLog("Failed to decode environments: \(error)")
            return []
        }
    }

    func createEnvironment(vaultId: String, name: String) -> Bool {
        vaultId.withCString { vId in
            name.withCString { n in
                vault0_create_environment(vId, n)
            }
        }
    }

    func deleteEnvironment(vaultId: String, name: String) -> Bool {
        vaultId.withCString { vId in
            name.withCString { n in
                vault0_delete_environment(vId, n)
            }
        }
    }

    func startServer() -> Bool {
        let result = vault0_server_start()
        NSLog(result ? "Server started successfully" : "Failed to start server")
        return result
    }

    func stopServer() {
        vault0_server_stop()
        NSLog("Server stopped")
    }

    func createApiKey(name: String, vaultId: String, environment: String, expirationDays: Int32) -> ApiKeyResponse? {
        let jsonPtr = name.withCString { namePtr in
            vaultId.withCString { vaultIdPtr in
                environment.withCString { envPtr in
                    vault0_create_api_key(namePtr, vaultIdPtr, envPtr, expirationDays)
                }
            }
        }

        guard let ptr = jsonPtr else {
            NSLog("vault0_create_api_key returned null")
            return nil
        }

        defer { vault0_free_string(ptr) }

        let jsonString = String(cString: ptr)
        guard let data = jsonString.data(using: .utf8) else {
            NSLog("Failed to convert JSON string to data")
            return nil
        }

        do {
            let response = try JSONDecoder().decode(ApiKeyResponse.self, from: data)
            NSLog("Created API key: \(response.apiKey.name)")
            return response
        } catch {
            NSLog("Failed to decode API key response: \(error)")
            return nil
        }
    }

    func listApiKeys(vaultId: String?) -> [ApiKey] {
        let jsonPtr: UnsafeMutablePointer<CChar>? = if let vaultId {
            vaultId.withCString { vault0_list_api_keys($0) }
        } else {
            vault0_list_api_keys(nil)
        }

        guard let ptr = jsonPtr else {
            NSLog("vault0_list_api_keys returned null")
            return []
        }

        defer { vault0_free_string(ptr) }

        let jsonString = String(cString: ptr)
        guard let data = jsonString.data(using: .utf8) else {
            NSLog("Failed to convert JSON string to data")
            return []
        }

        do {
            let apiKeys = try JSONDecoder().decode([ApiKey].self, from: data)
            NSLog("Loaded \(apiKeys.count) API keys")
            return apiKeys
        } catch {
            NSLog("Failed to decode API keys: \(error)")
            return []
        }
    }

    func deleteApiKey(id: String) -> Bool {
        let result = id.withCString { vault0_delete_api_key($0) }
        NSLog(result ? "API key deleted successfully" : "Failed to delete API key")
        return result
    }

    func cleanupExpiredApiKeys() -> Int32 {
        vault0_cleanup_expired_api_keys()
    }
}
