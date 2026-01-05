import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var session: MasterPasswordSession
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var errorMessage: String = ""
    @State private var isLoading: Bool = false
    @FocusState private var focusedField: Field?

    enum Field {
        case password
        case confirmPassword
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)
                .clipShape(Circle())

            VStack(spacing: 8) {
                Text("Welcome to Vault0")
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                Text("Securely manage your environment variables")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 16) {
                Text("Create Master Password")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 12) {
                    SecureField("Master Password", text: $password)
                        .customTextField(isError: !errorMessage.isEmpty && password.isEmpty)
                        .frame(width: 360)
                        .focused($focusedField, equals: .password)
                        .onSubmit {
                            focusedField = .confirmPassword
                        }

                    SecureField("Confirm Password", text: $confirmPassword)
                        .customTextField(isError: !errorMessage.isEmpty && confirmPassword.isEmpty)
                        .frame(width: 360)
                        .focused($focusedField, equals: .confirmPassword)
                        .onSubmit {
                            createMasterPassword()
                        }

                    if !errorMessage.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.caption)
                            Text(errorMessage)
                                .font(.caption)
                        }
                        .foregroundColor(.red)
                    }

                    passwordStrengthIndicator
                }
            }
            .padding(.top, 8)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.vault0Warning)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Please remember your master password")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.vault0TextPrimary)
                    Text("For your security, Vault0 cannot recover your master password. If forgotten, your stored secrets will be permanently inaccessible.")
                        .font(.system(size: 11))
                        .foregroundColor(.vault0TextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(width: 360, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.vault0Warning.opacity(0.08)),
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.vault0Warning.opacity(0.2), lineWidth: 1),
            )

            Button(action: createMasterPassword) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Text("Create Master Password")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!isPasswordValid || isLoading)
            .frame(width: 360)

            Spacer()
            Spacer()
        }
        .frame(width: 520)
        .frame(minHeight: 560)
        .padding(32)
        .onAppear {
            focusedField = .password
        }
    }

    private var passwordStrengthIndicator: some View {
        Group {
            if !password.isEmpty {
                let strength = getPasswordStrength()
                HStack {
                    Text("Password strength:")
                        .font(.caption)
                    Text(strength.text)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(strength.color)
                }
            }
        }
    }

    private var isPasswordValid: Bool {
        !password.isEmpty && password == confirmPassword
    }

    private func getPasswordStrength() -> (text: String, color: Color) {
        let length = password.count
        let hasUppercase = password.range(of: "[A-Z]", options: .regularExpression) != nil
        let hasLowercase = password.range(of: "[a-z]", options: .regularExpression) != nil
        let hasNumber = password.range(of: "[0-9]", options: .regularExpression) != nil
        let hasSpecial = password.range(of: "[^A-Za-z0-9]", options: .regularExpression) != nil

        let criteriaCount = [hasUppercase, hasLowercase, hasNumber, hasSpecial].count(where: { $0 })

        if length >= 12, criteriaCount >= 3 {
            return ("Strong", .green)
        } else if length >= 6, criteriaCount >= 2 {
            return ("Medium", .orange)
        } else {
            return ("Weak", .red)
        }
    }

    private func createMasterPassword() {
        guard password == confirmPassword else {
            errorMessage = "Passwords do not match"
            return
        }

        isLoading = true
        errorMessage = ""

        DispatchQueue.global(qos: .userInitiated).async {
            let success = Vault0Library.shared.createMasterPassword(password)

            DispatchQueue.main.async {
                isLoading = false
                if success {
                    NSLog("Master password created successfully")
                    _ = Vault0Library.shared.setOnboardingCompleted()
                    session.setSessionPassword(password)
                    WindowManager.shared.showMainWindow()
                } else {
                    errorMessage = "Failed to create master password"
                    NSLog("Failed to create master password")
                }
            }
        }
    }
}
