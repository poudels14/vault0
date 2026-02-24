import SwiftUI

struct AddSecretDialog: View {
    @Environment(\.dismiss) var dismiss
    let vaultId: String
    let defaultEnvironment: String
    let defaultKey: String?
    let existingSecrets: [Secret]
    let onSave: (String, String, String, String) -> Void

    @State private var environment: String
    @State private var key: String
    @State private var value: String = ""
    @State private var showValue: Bool = false
    @State private var keyError: String?

    init(vaultId: String, defaultEnvironment: String = "development", defaultKey: String? = nil, existingSecrets: [Secret] = [], onSave: @escaping (String, String, String, String) -> Void) {
        self.vaultId = vaultId
        self.defaultEnvironment = defaultEnvironment
        self.defaultKey = defaultKey
        self.existingSecrets = existingSecrets
        self.onSave = onSave
        _environment = State(initialValue: defaultEnvironment)
        _key = State(initialValue: defaultKey ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add Secret")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.vault0TextPrimary)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.vault0TextSecondary)
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(Color.vault0Surface),
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()
                .background(Color.vault0Border)

            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Key")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.vault0TextSecondary)

                    if defaultKey != nil {
                        Text(key)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(.vault0TextPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color.vault0Surface)
                            .cornerRadius(8)
                    } else {
                        TextField("e.g., DATABASE_URL", text: $key)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(minWidth: 0, maxWidth: .infinity)
                            .customTextField(isError: keyError != nil)
                            .onChange(of: key) { newValue in
                                validateKey(newValue)
                            }

                        if let error = keyError {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.system(size: 11))
                                Text(error)
                                    .font(.system(size: 11))
                            }
                            .foregroundColor(.vault0Error)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Value")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.vault0TextSecondary)
                    HStack(alignment: .top, spacing: 8) {
                        Group {
                            if showValue {
                                ZStack(alignment: .topLeading) {
                                    if value.isEmpty {
                                        Text("Enter value")
                                            .font(.system(size: 13))
                                            .foregroundColor(.vault0TextTertiary)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 14)
                                            .allowsHitTesting(false)
                                    }

                                    TextEditor(text: $value)
                                        .font(.system(size: 13, design: .monospaced))
                                        .foregroundColor(.vault0TextPrimary)
                                        .scrollContentBackground(.hidden)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 6)
                                }
                                .frame(height: 96)
                                .background(Color.vault0Background)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.vault0Border, lineWidth: 1),
                                )
                            } else {
                                SecureField("Enter value", text: $value)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .customTextField()
                                    .padding(.top, 2)
                            }
                        }
                        .frame(minWidth: 0, maxWidth: .infinity)
                        .layoutPriority(1)
                        Button(action: { showValue.toggle() }) {
                            Image(systemName: showValue ? "eye.slash" : "eye")
                                .font(.system(size: 13))
                                .foregroundColor(.vault0TextSecondary)
                                .frame(width: 32, height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.vault0Surface),
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(20)

            Spacer()

            Divider()
                .background(Color.vault0Border)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(SecondaryButtonStyle())
                .frame(width: 100)

                Button("Save") {
                    saveSecret()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!isValid)
                .frame(width: 100)
            }
            .padding(20)
        }
        .frame(width: 480, height: 420)
        .background(Color.vault0Background)
    }

    private var isValid: Bool {
        let trimmedKey = key.trimmingCharacters(in: .whitespaces)
        return !trimmedKey.isEmpty &&
            !trimmedKey.contains(" ") &&
            !value.isEmpty &&
            keyError == nil
    }

    private func validateKey(_ newValue: String) {
        if newValue.contains(" ") {
            keyError = "Key cannot contain spaces"
        } else if defaultKey == nil, secretExists(key: newValue) {
            keyError = "Secret '\(newValue)' already exists"
        } else {
            keyError = nil
        }
    }

    private func secretExists(key: String) -> Bool {
        let trimmedKey = key.trimmingCharacters(in: .whitespaces)
        guard !trimmedKey.isEmpty else { return false }

        return existingSecrets.contains { secret in
            secret.key == trimmedKey &&
                secret.environment.lowercased() == environment.lowercased()
        }
    }

    private func saveSecret() {
        let trimmedKey = key.trimmingCharacters(in: .whitespaces)
        guard !trimmedKey.contains(" ") else {
            keyError = "Key cannot contain spaces"
            return
        }

        guard !secretExists(key: trimmedKey) else {
            keyError = "Secret '\(trimmedKey)' already exists"
            return
        }

        onSave(vaultId, environment, trimmedKey, value)
        dismiss()
    }
}
