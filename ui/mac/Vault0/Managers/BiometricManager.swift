import Foundation
import LocalAuthentication
import Security

class BiometricManager {
    static let shared = BiometricManager()

    private init() {}

    func isBiometricAvailable() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    func biometricType() -> String {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return "None"
        }

        switch context.biometryType {
        case .touchID:
            return "Touch ID"
        case .faceID:
            return "Face ID"
        case .opticID:
            return "Optic ID"
        default:
            return "Biometric"
        }
    }

    func authenticateToUnlock(reason: String = "Unlock Vault0", completion: @escaping (Result<Void, Error>) -> Void) {
        let context = LAContext()
        context.localizedCancelTitle = "Enter Password"

        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, authError in
            DispatchQueue.main.async {
                if success {
                    NSLog("Biometric authentication succeeded")
                    completion(.success(()))
                } else {
                    NSLog("Biometric authentication failed: \(String(describing: authError))")
                    if let error = authError {
                        completion(.failure(error))
                    } else {
                        completion(.failure(BiometricError.authenticationFailed))
                    }
                }
            }
        }
    }
}

enum BiometricError: LocalizedError {
    case notAvailable
    case authenticationFailed
    case invalidData
    case keychainError(OSStatus)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            "Biometric authentication is not available"
        case .authenticationFailed:
            "Biometric authentication failed"
        case .invalidData:
            "Invalid password data"
        case let .keychainError(status):
            "Keychain error: \(status)"
        }
    }
}
