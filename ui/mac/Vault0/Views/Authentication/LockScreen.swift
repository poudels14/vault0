import LocalAuthentication
import SwiftUI

struct LockScreenView: View {
    @EnvironmentObject var session: MasterPasswordSession
    @State private var password: String = ""
    @State private var errorMessage: String = ""
    @State private var isLoading: Bool = false
    @State private var showPasswordField: Bool = false
    @FocusState private var isPasswordFocused: Bool

    private var biometricAvailable: Bool {
        BiometricManager.shared.isBiometricAvailable()
    }

    private var biometricType: String {
        BiometricManager.shared.biometricType()
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.fill")
                .font(.system(size: 56))
                .foregroundColor(.blue)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 8) {
                Text("Vault0 is Locked")
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                Text(biometricAvailable ? "Use \(biometricType) to unlock" : "Enter your password to unlock")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if showPasswordField {
                VStack(alignment: .leading, spacing: 8) {
                    SecureField("Master Password", text: $password, onCommit: unlockWithPassword)
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

                Button(action: unlockWithPassword) {
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
            } else if biometricAvailable {
                Button(action: unlockWithBiometric) {
                    HStack(spacing: 12) {
                        Image(systemName: biometricType == "Face ID" ? "faceid" : "touchid")
                            .font(.system(size: 20))
                        Text("Unlock with \(biometricType)")
                            .font(.system(size: 16, weight: .medium))
                    }
                    .frame(width: 320)
                    .padding(.vertical, 12)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isLoading)

                Button("Use Password Instead") {
                    showPasswordField = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isPasswordFocused = true
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.vault0Accent)
                .padding(.top, 8)
            }

            Spacer()
            Spacer()
        }
        .frame(width: 480)
        .frame(minHeight: 420)
        .padding(32)
        .onAppear {
            if biometricAvailable {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    unlockWithBiometric()
                }
            } else {
                showPasswordField = true
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

    private func unlockWithPassword() {
        guard !password.isEmpty else { return }

        isLoading = true
        errorMessage = ""

        DispatchQueue.global(qos: .userInitiated).async {
            let isValid = Vault0Library.shared.verifyMasterPassword(password)

            DispatchQueue.main.async {
                isLoading = false

                if isValid {
                    session.unlock()
                    password = ""
                    WindowManager.shared.showMainWindow()
                } else {
                    errorMessage = "Incorrect password"
                    password = ""
                    isPasswordFocused = true
                }
            }
        }
    }
}
