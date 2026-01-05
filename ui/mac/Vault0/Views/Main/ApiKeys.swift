import SwiftUI

struct ManageApiKeys: View {
    let selectedVaultId: String?
    let selectedEnvironment: String
    let vaults: [Vault]
    let onRefresh: () -> Void

    @State private var apiKeys: [ApiKey] = []
    @State private var showCreateSheet = false
    @State private var showTokenSheet = false
    @State private var generatedToken: String?
    @State private var generatedSecret: String?
    @State private var generatedKeyName: String?
    @State private var isLoading = false
    @State private var searchText = ""
    @State private var loadedVaultId: String?

    var filteredApiKeys: [ApiKey] {
        var filtered = apiKeys.filter { apiKey in
            (loadedVaultId == nil || apiKey.vaultId == loadedVaultId) &&
                apiKey.environment.lowercased() == selectedEnvironment.lowercased()
        }

        if !searchText.isEmpty {
            filtered = filtered.filter { apiKey in
                apiKey.name.localizedCaseInsensitiveContains(searchText)
            }
        }
        return filtered
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                SearchField(text: $searchText, placeholder: "Search API keys...")

                Button(action: {
                    guard selectedVaultId != nil else { return }
                    showCreateSheet = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                        Text("New Key")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(.vault0Accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.vault0Accent.opacity(0.08)),
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.vault0Accent.opacity(0.15), lineWidth: 1),
                    )
                }
                .buttonStyle(.plain)
                .disabled(selectedVaultId == nil)
                .opacity(selectedVaultId == nil ? 0.5 : 1.0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.vault0Background)

            Divider()
                .background(Color.vault0Border)

            if selectedVaultId == nil {
                emptyVaultView
            } else if filteredApiKeys.isEmpty, !isLoading {
                emptyApiKeysView
            } else {
                apiKeysListContent
            }
        }
        .background(Color.vault0Background)
        .sheet(isPresented: $showCreateSheet) {
            if let vaultId = selectedVaultId {
                CreateApiKeyDialog(
                    preselectedVaultId: vaultId,
                    preselectedEnvironment: selectedEnvironment,
                    vaults: vaults,
                    onCreate: { name, vaultId, environment, expiration in
                        createApiKey(name: name, vaultId: vaultId, environment: environment, expiration: expiration)
                    },
                )
            }
        }
        .sheet(isPresented: $showTokenSheet) {
            ApiKeyTokenSheet(
                token: generatedToken ?? "",
                secret: generatedSecret ?? "",
                keyName: generatedKeyName ?? "",
            )
        }
        .task(id: selectedVaultId) {
            searchText = ""
            apiKeys = []
            loadData()
        }
    }

    private var emptyVaultView: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.viewfinder")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(.vault0TextTertiary)
            Text("Select a Vault")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.vault0TextPrimary)
            Text("Choose a vault from the sidebar to manage API keys")
                .font(.system(size: 13))
                .foregroundColor(.vault0TextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.vault0Background)
    }

    private var emptyApiKeysView: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.horizontal")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(.vault0TextTertiary)
            Text(searchText.isEmpty ? "No API Keys" : "No Results")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.vault0TextPrimary)
            Text(searchText.isEmpty ? "Create an API key to access secrets from CI/CD" : "Try a different search term")
                .font(.system(size: 13))
                .foregroundColor(.vault0TextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.vault0Background)
    }

    private var apiKeysListContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(filteredApiKeys.enumerated()), id: \.element.id) { index, apiKey in
                    ApiKeyRow(apiKey: apiKey, vaults: vaults, onDelete: {
                        deleteApiKey(apiKey)
                    })

                    if index < filteredApiKeys.count - 1 {
                        Divider()
                            .padding(.horizontal, 20)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .background(Color.vault0Background)
    }

    private func loadData() {
        guard let vaultId = selectedVaultId else {
            apiKeys = []
            loadedVaultId = nil
            isLoading = false
            return
        }

        isLoading = true
        let keys = Vault0Library.shared.listApiKeys(vaultId: vaultId)
        if selectedVaultId == vaultId {
            apiKeys = keys
            loadedVaultId = vaultId
            isLoading = false
        }
    }

    private func createApiKey(name: String, vaultId: String, environment: String, expiration: ApiKeyExpiration) {
        if let response = Vault0Library.shared.createApiKey(
            name: name,
            vaultId: vaultId,
            environment: environment,
            expirationDays: expiration.rawValue,
        ) {
            generatedToken = response.jwtToken
            generatedSecret = response.apiSecret
            generatedKeyName = response.apiKey.name
            showCreateSheet = false
            showTokenSheet = true
            loadData()
            onRefresh()
        }
    }

    private func deleteApiKey(_ apiKey: ApiKey) {
        if Vault0Library.shared.deleteApiKey(id: apiKey.id) {
            loadData()
            onRefresh()
        }
    }
}

struct ApiKeyRow: View {
    let apiKey: ApiKey
    let vaults: [Vault]
    let onDelete: () -> Void

    @State private var isHovering = false
    @State private var showingDeleteAlert = false

    var vaultName: String {
        vaults.first(where: { $0.id == apiKey.vaultId })?.name ?? "Unknown Vault"
    }

    private func formatExpiration(_ date: Date) -> String {
        let now = Date()
        let interval = date.timeIntervalSince(now)

        if interval <= 0 {
            return "Expired"
        }

        let days = Int(ceil(interval / 86400))
        if days == 1 {
            return "Expires tomorrow"
        } else if days <= 7 {
            return "Expires in \(days) days"
        } else if days <= 30 {
            let weeks = days / 7
            return "Expires in \(weeks)w"
        } else {
            let months = days / 30
            return "Expires in \(months)mo"
        }
    }

    private func formatLastUsed(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        let minutes = Int(interval / 60)
        let hours = Int(interval / 3600)
        let days = Int(interval / 86400)

        if minutes < 1 {
            return "Used just now"
        } else if minutes < 60 {
            return "Used \(minutes)m ago"
        } else if hours < 24 {
            return "Used \(hours)h ago"
        } else {
            return "Used \(days)d ago"
        }
    }

    private var statusText: String {
        if apiKey.isExpired {
            "Expired"
        } else if let expirationDate = apiKey.expirationDate {
            formatExpiration(expirationDate)
        } else {
            "Never expires"
        }
    }

    private var statusColor: Color {
        if apiKey.isExpired {
            return .vault0Error
        } else if let expirationDate = apiKey.expirationDate {
            let daysLeft = Int(ceil(expirationDate.timeIntervalSince(Date()) / 86400))
            return daysLeft <= 7 ? .vault0Warning : .vault0TextTertiary
        } else {
            return .vault0TextTertiary
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(apiKey.isExpired ? Color.vault0Error : Color.vault0Success)
                        .frame(width: 6, height: 6)
                    Text(apiKey.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(apiKey.isExpired ? .vault0TextTertiary : .vault0TextPrimary)
                }

                HStack(spacing: 8) {
                    Text(statusText)
                        .foregroundColor(statusColor)

                    if let lastUsedDate = apiKey.lastUsedDate {
                        Text("·")
                            .foregroundColor(.vault0TextTertiary)
                        Text(formatLastUsed(lastUsedDate))
                            .foregroundColor(.vault0TextTertiary)
                    } else {
                        Text("·")
                            .foregroundColor(.vault0TextTertiary)
                        Text("Never used")
                            .foregroundColor(.vault0TextTertiary)
                    }
                }
                .font(.system(size: 11, weight: .light))
                .padding(.leading, 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 2) {
                if isHovering {
                    ActionButton(
                        icon: "trash",
                        action: { showingDeleteAlert = true },
                        hoverColor: .vault0Error,
                    )
                    .help("Delete API key")
                }
            }
            .frame(width: 40)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(isHovering ? Color.vault0Surface.opacity(0.5) : Color.clear)
        .opacity(apiKey.isExpired ? 0.7 : 1.0)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
        .alert("Delete API Key", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive, action: onDelete)
        } message: {
            Text("Are you sure you want to delete \"\(apiKey.name)\"? Any services using this key will lose access.")
        }
    }
}

struct CreateApiKeyDialog: View {
    @Environment(\.dismiss) var dismiss
    let preselectedVaultId: String
    let preselectedEnvironment: String
    let vaults: [Vault]
    let onCreate: (String, String, String, ApiKeyExpiration) -> Void

    @State private var name = ""
    @State private var selectedEnvironment: String
    @State private var selectedExpiration: ApiKeyExpiration = .ninetyDays
    @State private var environments: [String] = []
    @FocusState private var isNameFocused: Bool

    init(preselectedVaultId: String, preselectedEnvironment: String, vaults: [Vault], onCreate: @escaping (String, String, String, ApiKeyExpiration) -> Void) {
        self.preselectedVaultId = preselectedVaultId
        self.preselectedEnvironment = preselectedEnvironment
        self.vaults = vaults
        self.onCreate = onCreate
        _selectedEnvironment = State(initialValue: preselectedEnvironment)
    }

    var selectedVault: Vault? {
        vaults.first(where: { $0.id == preselectedVaultId })
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Create API Key")
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
                .keyboardShortcut(.cancelAction)
            }
            .padding(20)

            Divider()
                .background(Color.vault0Border)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Name")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.vault0TextSecondary)
                        TextField("e.g., Production CI/CD", text: $name)
                            .customTextField()
                            .focused($isNameFocused)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Vault")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.vault0TextSecondary)
                        HStack(spacing: 10) {
                            Image(systemName: "tray.full")
                                .font(.system(size: 13))
                                .foregroundColor(.vault0Accent)
                            if let vault = selectedVault {
                                Text(vault.name)
                                    .font(.system(size: 13))
                                    .foregroundColor(.vault0TextPrimary)
                            } else {
                                Text("Unknown Vault")
                                    .font(.system(size: 13))
                                    .foregroundColor(.vault0TextTertiary)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(Color.vault0Surface)
                        .cornerRadius(8)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Expiration")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.vault0TextSecondary)
                        Menu {
                            ForEach(ApiKeyExpiration.allCases) { expiration in
                                Button(action: { selectedExpiration = expiration }) {
                                    HStack {
                                        Text(expiration.displayName)
                                        Spacer()
                                        if selectedExpiration == expiration {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "calendar")
                                    .font(.system(size: 13))
                                    .foregroundColor(.vault0Accent)
                                Text(selectedExpiration.displayName)
                                    .font(.system(size: 13))
                                    .foregroundColor(.vault0TextPrimary)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.vault0TextTertiary)
                            }
                            .padding(12)
                            .background(Color.vault0Background)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.vault0Border, lineWidth: 1),
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 13))
                            .foregroundColor(.vault0Accent)
                        Text("This key will have access to all secrets in this vault and environment.")
                            .font(.system(size: 12))
                            .foregroundColor(.vault0TextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.vault0Accent.opacity(0.06)),
                    )
                }
                .padding(20)
            }

            Divider()
                .background(Color.vault0Border)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(SecondaryButtonStyle())
                .frame(width: 100)

                Button("Create") {
                    onCreate(name, preselectedVaultId, selectedEnvironment, selectedExpiration)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(name.isEmpty)
                .frame(width: 100)
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 480)
        .background(Color.vault0Background)
        .onAppear {
            environments = Vault0Library.shared.listEnvironments(vaultId: preselectedVaultId)
            isNameFocused = true
        }
    }
}

struct ApiKeyTokenSheet: View {
    @Environment(\.dismiss) var dismiss
    let token: String
    let secret: String
    let keyName: String

    @State private var copiedToken = false
    @State private var copiedSecret = false
    @State private var copiedExportKey = false
    @State private var copiedExportSecret = false
    @State private var copiedLoad = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.vault0Success)
                        Text("API Key Created")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.vault0TextPrimary)
                    }
                    Text("Copy both values now - you won't see them again")
                        .font(.system(size: 12))
                        .foregroundColor(.vault0TextSecondary)
                }
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
                .keyboardShortcut(.cancelAction)
            }
            .padding(20)

            Divider()
                .background(Color.vault0Border)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Key Name")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.vault0TextSecondary)
                        HStack(spacing: 10) {
                            Image(systemName: "key.horizontal")
                                .font(.system(size: 13))
                                .foregroundColor(.vault0Accent)
                            Text(keyName)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.vault0TextPrimary)
                            Spacer()
                        }
                        .padding(12)
                        .background(Color.vault0Surface)
                        .cornerRadius(8)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("API Key")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.vault0TextSecondary)
                            Text("(VAULT0_API_KEY)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.vault0TextTertiary)
                            Spacer()
                            CopyButton(
                                text: token,
                                copied: $copiedToken,
                                label: "Copy",
                            )
                        }

                        Text(token)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.vault0TextSecondary)
                            .textSelection(.enabled)
                            .lineLimit(3)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color.vault0Surface)
                            .cornerRadius(8)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("API Secret")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.vault0TextSecondary)
                            Text("(VAULT0_API_SECRET)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.vault0TextTertiary)
                            Spacer()
                            CopyButton(
                                text: secret,
                                copied: $copiedSecret,
                                label: "Copy",
                            )
                        }

                        Text(secret)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.vault0TextSecondary)
                            .textSelection(.enabled)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color.vault0Surface)
                            .cornerRadius(8)

                        HStack(spacing: 6) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10))
                            Text("Keep this secret secure - it's used to decrypt your secrets")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(.vault0Warning)
                    }

                    // Usage instructions
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Quick Start")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.vault0TextPrimary)

                        // Step 1
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("1")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.vault0Accent)
                                    .frame(width: 18, height: 18)
                                    .background(
                                        Circle()
                                            .fill(Color.vault0Accent.opacity(0.12)),
                                    )
                                Text("Export the API key")
                                    .font(.system(size: 12))
                                    .foregroundColor(.vault0TextSecondary)
                                Spacer()
                                CopyButton(
                                    text: "export VAULT0_API_KEY=\"\(token)\"",
                                    copied: $copiedExportKey,
                                    label: "Copy",
                                )
                            }
                            Text("export VAULT0_API_KEY=\"...\"")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.vault0TextTertiary)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.vault0Surface)
                                .cornerRadius(6)
                        }

                        // Step 2
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("2")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.vault0Accent)
                                    .frame(width: 18, height: 18)
                                    .background(
                                        Circle()
                                            .fill(Color.vault0Accent.opacity(0.12)),
                                    )
                                Text("Export the API secret")
                                    .font(.system(size: 12))
                                    .foregroundColor(.vault0TextSecondary)
                                Spacer()
                                CopyButton(
                                    text: "export VAULT0_API_SECRET=\"\(secret)\"",
                                    copied: $copiedExportSecret,
                                    label: "Copy",
                                )
                            }
                            Text("export VAULT0_API_SECRET=\"...\"")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.vault0TextTertiary)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.vault0Surface)
                                .cornerRadius(6)
                        }

                        // Step 3
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("3")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.vault0Accent)
                                    .frame(width: 18, height: 18)
                                    .background(
                                        Circle()
                                            .fill(Color.vault0Accent.opacity(0.12)),
                                    )
                                Text("Load secrets into your shell")
                                    .font(.system(size: 12))
                                    .foregroundColor(.vault0TextSecondary)
                                Spacer()
                                CopyButton(
                                    text: "eval \"$(vault0 load)\"",
                                    copied: $copiedLoad,
                                    label: "Copy",
                                )
                            }
                            Text("eval \"$(vault0 load)\"")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.vault0TextTertiary)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.vault0Surface)
                                .cornerRadius(6)
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.vault0Accent.opacity(0.04)),
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.vault0Accent.opacity(0.1), lineWidth: 1),
                    )
                }
                .padding(20)
            }

            Divider()
                .background(Color.vault0Border)

            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .frame(width: 100)
            }
            .padding(20)
        }
        .frame(width: 560, height: 620)
        .background(Color.vault0Background)
    }
}

struct CopyButton: View {
    let text: String
    @Binding var copied: Bool
    var label: String = "Copy"

    var body: some View {
        Button(action: {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                copied = false
            }
        }) {
            HStack(spacing: 4) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10, weight: .medium))
                Text(copied ? "Copied!" : label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(copied ? .vault0Success : .vault0Accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(copied ? Color.vault0Success.opacity(0.1) : Color.vault0Accent.opacity(0.08)),
            )
        }
        .buttonStyle(.plain)
    }
}
