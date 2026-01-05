import SwiftUI

struct ManageVaultsDialog: View {
    @Environment(\.dismiss) var dismiss
    @Binding var vaults: [Vault]
    @Binding var isLoading: Bool
    @State private var showingAddSheet: Bool = false
    @State private var editingVault: Vault?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Manage Vaults")
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

            VStack(spacing: 0) {
                if isLoading {
                    ProgressView("Loading vaults...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vaults.isEmpty {
                    emptyStateView
                } else {
                    vaultsListContent
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddVaultDialog(onSave: handleCreateVault)
            }
            .sheet(item: $editingVault) { vault in
                AddVaultDialog(vault: vault, onSave: { name, description in
                    handleUpdateVault(id: vault.id, name: name, description: description)
                })
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingAddSheet = true }) {
                        Label("Add Vault", systemImage: "plus")
                    }
                }
            }
        }
        .frame(width: 500, height: 400)
        .background(Color.vault0Background)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "archivebox")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(.vault0TextTertiary)
            Text("No Vaults Yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.vault0TextPrimary)
            Text("Create a vault to organize your secrets")
                .font(.system(size: 13))
                .foregroundColor(.vault0TextSecondary)
                .multilineTextAlignment(.center)
            Button(action: { showingAddSheet = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Create Vault")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.vault0Accent)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.vault0Background)
    }

    private var vaultsListContent: some View {
        List(vaults) { vault in
            VaultRow(vault: vault, onEdit: {
                editingVault = vault
            }, onDelete: {
                deleteVault(vault)
            })
        }
        .listStyle(.inset)
    }

    private func handleCreateVault(name: String, description: String?) {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let vaultId = Vault0Library.shared.createVault(name: name, description: description)
            DispatchQueue.main.async {
                if let id = vaultId {
                    NSLog("Vault created successfully with ID: \(id)")
                    refreshVaults()
                } else {
                    NSLog("Failed to create vault")
                    isLoading = false
                }
            }
        }
    }

    private func handleUpdateVault(id: String, name: String, description: String?) {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let success = Vault0Library.shared.updateVault(id: id, name: name, description: description)
            DispatchQueue.main.async {
                if success {
                    NSLog("Vault updated successfully")
                    editingVault = nil
                    refreshVaults()
                } else {
                    NSLog("Failed to update vault")
                    isLoading = false
                }
            }
        }
    }

    private func deleteVault(_ vault: Vault) {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let success = Vault0Library.shared.deleteVault(id: vault.id)
            DispatchQueue.main.async {
                if success {
                    NSLog("Vault deleted successfully")
                    refreshVaults()
                } else {
                    NSLog("Failed to delete vault")
                    isLoading = false
                }
            }
        }
    }

    private func refreshVaults() {
        DispatchQueue.global(qos: .userInitiated).async {
            let loaded = Vault0Library.shared.listVaults()
            DispatchQueue.main.async {
                vaults = loaded
                isLoading = false
            }
        }
    }
}

struct VaultRow: View {
    let vault: Vault
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var showingDeleteAlert = false

    private func formattedCreatedDate(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        let minutes = Int(interval / 60)
        let hours = Int(interval / 3600)
        let days = Int(interval / 86400)

        if minutes < 1 {
            return "just now"
        } else if minutes < 60 {
            return "\(minutes) minute\(minutes == 1 ? "" : "s") ago"
        } else if hours < 24 {
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        } else if days < 30 {
            return "\(days) day\(days == 1 ? "" : "s") ago"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "archivebox.fill")
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 32, height: 32)
                .background(Color.vault0Accent.opacity(0.1))
                .cornerRadius(6)

            VStack(alignment: .leading, spacing: 4) {
                Text(vault.name)
                    .font(.body.weight(.medium))

                if let description = vault.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Text("Created \(formattedCreatedDate(vault.createdDate))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                Button(action: onEdit) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 12))
                        .foregroundColor(.vault0Accent)
                }
                .buttonStyle(.plain)
                .help("Edit vault")

                TrashButton {
                    showingDeleteAlert = true
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .alert("Delete Vault", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive, action: onDelete)
        } message: {
            Text("Are you sure you want to delete '\(vault.name)'? All secrets and mappings in this vault will be deleted.")
        }
    }
}
