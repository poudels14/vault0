import SwiftUI

struct AddVaultDialog: View {
    @Environment(\.dismiss) var dismiss
    let vault: Vault?
    let onSave: (String, String?) -> Void

    @State private var name: String
    @State private var description: String
    @State private var nameError: String?

    init(vault: Vault? = nil, onSave: @escaping (String, String?) -> Void) {
        self.vault = vault
        self.onSave = onSave
        _name = State(initialValue: vault?.name ?? "")
        _description = State(initialValue: vault?.description ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(vault == nil ? "Create Vault" : "Edit Vault")
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

            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Vault Name")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.vault0TextSecondary)
                    TextField("My Vault", text: $name)
                        .customTextField(isError: nameError != nil)
                        .onChange(of: name) { newValue in
                            if newValue.contains(" ") {
                                nameError = "Vault name cannot contain spaces"
                            } else {
                                nameError = nil
                            }
                        }

                    if let error = nameError {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 11))
                            Text(error)
                                .font(.system(size: 11))
                        }
                        .foregroundColor(.vault0Error)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Description (optional)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.vault0TextSecondary)
                    TextEditor(text: $description)
                        .frame(height: 80)
                        .padding(8)
                        .font(.system(size: 13))
                        .background(Color.vault0Background)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.vault0Border, lineWidth: 1),
                        )
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

                Button(vault == nil ? "Create" : "Save") {
                    saveVault()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || nameError != nil)
                .frame(width: 100)
            }
            .padding(20)
        }
        .frame(width: 480, height: 400)
        .background(Color.vault0Background)
    }

    private func saveVault() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)

        guard !trimmedName.contains(" ") else {
            nameError = "Vault name cannot contain spaces"
            return
        }

        let trimmedDesc = description.trimmingCharacters(in: .whitespaces)
        let finalDesc = trimmedDesc.isEmpty ? nil : trimmedDesc

        onSave(trimmedName, finalDesc)
        dismiss()
    }
}
