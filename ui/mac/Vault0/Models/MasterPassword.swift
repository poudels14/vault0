import Combine
import Foundation

class MasterPasswordSession: ObservableObject {
    static let shared = MasterPasswordSession()

    @Published var isAuthenticated: Bool = false
    @Published var isLocked: Bool = false

    private(set) var sessionPassword: String?
    private var inactivityTimer: Timer?
    private let inactivityTimeout: TimeInterval = 60 // 1 minute

    private init() {}

    func setSessionPassword(_ password: String) {
        sessionPassword = password
        isAuthenticated = true
        isLocked = false
        _ = Vault0Library.shared.startServer()
        startInactivityTimer()
    }

    func lock() {
        stopInactivityTimer()
        isLocked = true
        NSLog("Session locked - password remains in memory, server still running")
    }

    func unlock() {
        guard sessionPassword != nil else {
            NSLog("Cannot unlock - no password in session")
            return
        }
        isLocked = false
        NSLog("Session unlocked - server still running")
        startInactivityTimer()
    }

    func unlockWithPassword(_ password: String) -> Bool {
        // Verify password and unlock (for when user enters password while locked)
        let isValid = Vault0Library.shared.verifyMasterPassword(password)

        if isValid {
            sessionPassword = password
            unlock()
            NSLog("Password verified and session unlocked - server continues running")
            return true
        } else {
            NSLog("Password verification failed")
            return false
        }
    }

    func clearSession() {
        stopInactivityTimer()
        Vault0Library.shared.stopServer()
        Vault0Library.shared.clearSession()

        sessionPassword = nil
        isAuthenticated = false
        isLocked = false
        NSLog("Session cleared - password removed from memory")
    }

    func resetInactivityTimer() {
        guard isAuthenticated, !isLocked else { return }
        startInactivityTimer()
    }

    private func startInactivityTimer() {
        stopInactivityTimer()
        inactivityTimer = Timer.scheduledTimer(withTimeInterval: inactivityTimeout, repeats: false) { [weak self] _ in
            self?.autoLock()
        }
    }

    private func stopInactivityTimer() {
        inactivityTimer?.invalidate()
        inactivityTimer = nil
    }

    private func autoLock() {
        guard isAuthenticated, !isLocked else { return }
        NSLog("Auto-locking app after 1 minute of inactivity")
        lock()
        WindowManager.shared.showLogin()
    }

    var needsAuthentication: Bool {
        !isAuthenticated || isLocked
    }

    deinit {
        clearSession()
    }
}
