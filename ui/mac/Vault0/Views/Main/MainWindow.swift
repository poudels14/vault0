import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject var session: MasterPasswordSession
    @State private var selectedVaultId: String?
    @State private var selectedEnvironment: String = ""
    @State private var vaults: [Vault] = []
    @State private var secrets: [Secret] = []
    @State private var isLoading: Bool = false
    @State private var showingAddVault: Bool = false
    @State private var showingSettings: Bool = false
    @State private var selectedTab: Tab = .secrets
    @State private var vaultEnvironments: [String] = []

    enum Tab: String, CaseIterable {
        case secrets = "Secrets"
        case apiKeys = "API Keys"
    }

    var body: some View {
        NavigationView {
            sidebarContent
            mainContent
        }
        .sheet(isPresented: $showingAddVault) {
            AddVaultDialog(onSave: handleCreateVault)
                .interactiveDismissDisabled(false)
        }
        .sheet(isPresented: $showingSettings) {
            ManageVaultsDialog(vaults: $vaults, isLoading: $isLoading)
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: lockApp) {
                    Image(systemName: "lock")
                        .font(.system(size: 13))
                }
                .help("Lock")
            }

            ToolbarItem(placement: .automatic) {
                Button(action: refreshData) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13))
                }
                .help("Refresh")
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .onAppear {
            refreshData()
        }
        .onChange(of: selectedVaultId) { _ in
            refreshVaultData()
        }
        .onChange(of: vaults) { newVaults in
            if let vaultId = selectedVaultId {
                if !newVaults.contains(where: { $0.id == vaultId }) {
                    selectedVaultId = nil
                }
            }
        }
    }

    private func loadVaultEnvironments() {
        guard let vaultId = selectedVaultId else {
            vaultEnvironments = []
            return
        }

        vaultEnvironments = Vault0Library.shared.listEnvironments(vaultId: vaultId)

        if !vaultEnvironments.contains(selectedEnvironment), let firstEnv = vaultEnvironments.first {
            selectedEnvironment = firstEnv
        }
    }

    private var sidebarContent: some View {
        VStack(spacing: 0) {
            SidebarVaultSection(
                vaults: vaults,
                selectedVaultId: $selectedVaultId,
                showingAddVault: $showingAddVault,
                showingSettings: $showingSettings,
            )

            Divider()

            SidebarEnvironmentSection(
                environments: vaultEnvironments,
                selectedVaultId: $selectedVaultId,
                selectedEnvironment: $selectedEnvironment,
                onEnvironmentsChanged: refreshVaultData,
            )

            Spacer()
        }
        .frame(minWidth: 200)
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            if selectedVaultId == nil {
                selectVaultPrompt
            } else if vaultEnvironments.isEmpty {
                noEnvironmentsPrompt
            } else {
                ContentTabPicker(selectedTab: $selectedTab)

                switch selectedTab {
                case .secrets:
                    SecretsListView(
                        vaultId: selectedVaultId,
                        selectedEnvironment: selectedEnvironment,
                        environments: vaultEnvironments,
                        secrets: $secrets,
                        isLoading: $isLoading,
                        onRefresh: refreshVaultData,
                    )
                case .apiKeys:
                    ManageApiKeys(
                        selectedVaultId: selectedVaultId,
                        selectedEnvironment: selectedEnvironment,
                        vaults: vaults,
                        onRefresh: refreshData,
                    )
                }
            }
        }
    }

    private var selectVaultPrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "archivebox")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("Select a Vault")
                .font(.title2)
                .fontWeight(.medium)
            Text("Choose a vault from the sidebar to view its contents")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noEnvironmentsPrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "server.rack")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No Environments")
                .font(.title2)
                .fontWeight(.medium)
            Text("Create an environment to start adding secrets")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func lockApp() {
        session.lock()
        WindowManager.shared.showLogin()
    }

    private func handleCreateVault(name: String, description: String?) {
        DispatchQueue.global(qos: .userInitiated).async {
            let vaultId = Vault0Library.shared.createVault(name: name, description: description)

            DispatchQueue.main.async {
                if let id = vaultId {
                    NSLog("Vault created successfully with ID: \(id)")
                    refreshData()
                    selectedVaultId = id
                } else {
                    NSLog("Failed to create vault")
                }
            }
        }
    }

    private func refreshData() {
        DispatchQueue.global(qos: .userInitiated).async {
            let loadedVaults = Vault0Library.shared.listVaults()

            DispatchQueue.main.async {
                vaults = loadedVaults

                if selectedVaultId == nil {
                    selectedVaultId = vaults.first?.id
                } else if let vaultId = selectedVaultId,
                          !vaults.contains(where: { $0.id == vaultId })
                {
                    selectedVaultId = vaults.first?.id
                }

                refreshVaultData()

                NSLog("Loaded \(vaults.count) vaults")
            }
        }
    }

    private func refreshVaultData() {
        guard let vaultId = selectedVaultId else {
            secrets = []
            vaultEnvironments = []
            isLoading = false
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let loadedSecrets = Vault0Library.shared.listSecrets(vaultId: vaultId, environment: nil)
            let loadedEnvs = Vault0Library.shared.listEnvironments(vaultId: vaultId)

            DispatchQueue.main.async {
                secrets = loadedSecrets
                vaultEnvironments = loadedEnvs
                isLoading = false

                if !vaultEnvironments.contains(selectedEnvironment), let firstEnv = vaultEnvironments.first {
                    selectedEnvironment = firstEnv
                }

                NSLog("Loaded \(secrets.count) secrets and \(vaultEnvironments.count) environments for vault \(vaultId)")
            }
        }
    }
}

struct SidebarVaultSection: View {
    let vaults: [Vault]
    @Binding var selectedVaultId: String?
    @Binding var showingAddVault: Bool
    @Binding var showingSettings: Bool

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Vault")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Button(action: { showingSettings = true }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Manage Vaults")
            }

            if vaults.isEmpty {
                emptyVaultsView
            } else {
                vaultMenu
            }
        }
        .padding(12)
    }

    private var emptyVaultsView: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "archivebox")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary.opacity(0.5))
                Text("No Vaults")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private var vaultMenu: some View {
        Menu {
            ForEach(vaults) { vault in
                Button(action: { selectedVaultId = vault.id }) {
                    HStack(spacing: 0) {
                        Text(vault.name)
                            .lineLimit(1)
                            .frame(maxWidth: 140, alignment: .leading)
                        Spacer(minLength: 8)
                        if selectedVaultId == vault.id {
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundColor(.vault0Accent)
                        }
                    }
                    .frame(minWidth: 180, alignment: .leading)
                    .padding(.vertical, 2)
                }
            }
            Divider()
            Button(action: { showingAddVault = true }) {
                Label("Add Vault", systemImage: "plus")
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "archivebox.fill")
                    .foregroundColor(.vault0Accent)
                    .font(.body)
                if let vaultId = selectedVaultId,
                   let vault = vaults.first(where: { $0.id == vaultId })
                {
                    Text(vault.name)
                        .font(.body)
                        .lineLimit(1)
                } else {
                    Text("Select Vault")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 0.5),
            )
        }
        .buttonStyle(.plain)
    }
}

struct SidebarEnvironmentSection: View {
    let environments: [String]
    @Binding var selectedVaultId: String?
    @Binding var selectedEnvironment: String
    let onEnvironmentsChanged: () -> Void

    @State private var showingManageSheet = false

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Environments")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Spacer()
                if selectedVaultId != nil {
                    Button(action: { showingManageSheet = true }) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Manage Environments")
                }
            }
            .padding(.vertical, 8)

            if environments.isEmpty {
                Text("No environments")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                ForEach(environments, id: \.self) { env in
                    SidebarEnvironmentButton(
                        title: env.capitalized,
                        isSelected: selectedEnvironment == env,
                        action: { selectedEnvironment = env },
                    )
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .sheet(isPresented: $showingManageSheet) {
            if let selectedVaultId {
                ManageEnvironmentsDialog(
                    vaultId: selectedVaultId,
                    environments: environments,
                    selectedEnvironment: $selectedEnvironment,
                    onChanged: onEnvironmentsChanged,
                )
            }
        }
    }
}

struct SidebarEnvironmentButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "server.rack")
                    .font(.system(size: 12))
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 13))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(isSelected ? Color.vault0Accent.opacity(0.12) : Color.clear)
            .cornerRadius(6)
            .foregroundColor(isSelected ? .vault0Accent : .primary)
        }
        .buttonStyle(.plain)
    }
}

struct ContentTabPicker: View {
    @Binding var selectedTab: MainWindowView.Tab

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(MainWindowView.Tab.allCases, id: \.self) { tab in
                    Button(action: { selectedTab = tab }) {
                        VStack(spacing: 0) {
                            HStack(spacing: 0) {
                                Image(systemName: tab == .secrets ? "key.fill" : "person.badge.key.fill")
                                    .font(.system(size: 12))
                                Text(tab.rawValue)
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundColor(selectedTab == tab ? .vault0Accent : .secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)

                            Rectangle()
                                .fill(selectedTab == tab ? Color.vault0Accent : Color.clear)
                                .frame(height: 2)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
    }
}
