import LocalAuthentication
import SwiftUI

struct LoginView: View {
    @EnvironmentObject var session: MasterPasswordSession
    @State private var password: String = ""
    @State private var errorMessage: String = ""
    @State private var isLoading: Bool = false
    @State private var showPasswordField: Bool = false
    @FocusState private var isPasswordFocused: Bool

    private var canUseBiometric: Bool {
        // Can use biometric if password is in memory (locked state)
        session.isAuthenticated && session.isLocked && BiometricManager.shared.isBiometricAvailable()
    }

    private var biometricType: String {
        BiometricManager.shared.biometricType()
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)
                .clipShape(Circle())

            VStack(spacing: 8) {
                Text("Vault0")
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                Text(canUseBiometric && !showPasswordField ? "Use \(biometricType) to unlock" : "Enter your master password")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if showPasswordField || !canUseBiometric {
                VStack(alignment: .leading, spacing: 8) {
                    SecureField("Master Password", text: $password, onCommit: login)
                        .customTextField(isError: !errorMessage.isEmpty)
                        .frame(width: 320)
                        .focused($isPasswordFocused)

                    if !errorMessage.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.caption)
                            Text(errorMessage)
                                .font(.caption)
                        }
                        .foregroundColor(.red)
                    }
                }
                .padding(.top, 8)

                Button(action: login) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Text("Unlock")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(password.isEmpty || isLoading)
                .frame(width: 320)
                .keyboardShortcut(.return)
            } else {
                VStack(spacing: 12) {
                    Button(action: unlockWithBiometric) {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .controlSize(.small)
                                .tint(.white)
                                .frame(width: 100, height: 24)
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: biometricType == "Face ID" ? "faceid" : "touchid")
                                    .font(.system(size: 14))
                                Text("Unlock with \(biometricType)")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .fixedSize()
                    .disabled(isLoading)

                    Button("Use Password Instead") {
                        showPasswordField = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isPasswordFocused = true
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.vault0Accent)
                    .font(.system(size: 12))
                }
            }

            Spacer()
            Spacer()
        }
        .frame(width: 480)
        .frame(minHeight: 420)
        .padding(32)
        .onAppear {
            if canUseBiometric, !showPasswordField {
                unlockWithBiometric()
            } else {
                isPasswordFocused = true
            }
        }
    }

    private func unlockWithBiometric() {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = ""

        BiometricManager.shared.authenticateToUnlock(reason: "Unlock Vault0") { result in
            switch result {
            case .success:
                NSLog("Biometric unlock succeeded")
                session.unlock()
                WindowManager.shared.showMainWindow()

            case let .failure(error):
                NSLog("Biometric unlock failed: \(error.localizedDescription)")
                if (error as NSError).code != LAError.userCancel.rawValue {
                    errorMessage = "Biometric authentication failed"
                    showPasswordField = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isPasswordFocused = true
                    }
                }
            }

            isLoading = false
        }
    }

    private func login() {
        guard !password.isEmpty else { return }

        isLoading = true
        errorMessage = ""

        let isUnlocking = session.isAuthenticated && session.isLocked
        let passwordToVerify = password
        DispatchQueue.global(qos: .userInitiated).async {
            let isValid: Bool = if isUnlocking {
                session.unlockWithPassword(passwordToVerify)
            } else {
                Vault0Library.shared.verifyMasterPassword(passwordToVerify)
            }

            DispatchQueue.main.async {
                isLoading = false
                if isValid {
                    if !isUnlocking {
                        session.setSessionPassword(passwordToVerify)
                    }
                    proceedToMainWindow()
                } else {
                    errorMessage = "Incorrect password"
                    password = ""
                    isPasswordFocused = true
                }
            }
        }
    }

    private func proceedToMainWindow() {
        password = ""
        WindowManager.shared.showMainWindow()
    }
}
