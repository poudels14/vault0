import Foundation

enum AuthenticationState {
    case needsOnboarding
    case needsLogin
}

class SessionManager: ObservableObject {
    static let shared = SessionManager()

    private init() {}

    func getAuthenticationState() -> AuthenticationState {
        let hasMasterPassword = Vault0Library.shared.hasMasterPassword()
        if !hasMasterPassword {
            NSLog("First-time user detected - onboarding needed")
            return .needsOnboarding
        } else {
            NSLog("Existing user detected - login required")
            return .needsLogin
        }
    }
}
