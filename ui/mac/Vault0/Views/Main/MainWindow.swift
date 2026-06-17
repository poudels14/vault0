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
    @State private var vaultEnvironments: [String] = []
    @State private var environmentItems: [EnvironmentItem] = []
    @State private var opLoadToken: Int = 0

    var body: some View {
        HSplitView {
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
        .onChange(of: selectedEnvironment) { _ in
            loadSelectedEnvironmentSecrets()
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

        environmentItems = Vault0Library.shared.listEnvironmentItems(vaultId: vaultId)
        vaultEnvironments = environmentItems.map(\.name)

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
                environmentItems: environmentItems,
                selectedVaultId: $selectedVaultId,
                selectedEnvironment: $selectedEnvironment,
                onEnvironmentsChanged: refreshVaultData,
            )

            Spacer()
        }
        .frame(minWidth: 260, idealWidth: 260, maxWidth: 420)
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            if selectedVaultId == nil {
                selectVaultPrompt
            } else if vaultEnvironments.isEmpty {
                noEnvironmentsPrompt
            } else {
                SecretsListView(
                    vaultId: selectedVaultId,
                    selectedEnvironment: selectedEnvironment,
                    environments: vaultEnvironments,
                    environmentItems: environmentItems,
                    secrets: $secrets,
                    isLoading: $isLoading,
                    onRefresh: refreshVaultData,
                )
            }
        }
        .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
        .layoutPriority(1)
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
            // Only loads local environments' secrets; 1Password-backed envs are
            // fetched lazily when selected (see loadSelectedEnvironmentSecrets).
            let loadedSecrets = Vault0Library.shared.listSecrets(vaultId: vaultId, environment: nil)
            let loadedEnvItems = Vault0Library.shared.listEnvironmentItems(vaultId: vaultId)

            DispatchQueue.main.async {
                secrets = loadedSecrets
                environmentItems = loadedEnvItems
                vaultEnvironments = loadedEnvItems.map(\.name)

                if !vaultEnvironments.contains(selectedEnvironment), let firstEnv = vaultEnvironments.first {
                    selectedEnvironment = firstEnv
                }

                loadSelectedEnvironmentSecrets()

                NSLog("Loaded \(secrets.count) secrets and \(vaultEnvironments.count) environments for vault \(vaultId)")
            }
        }
    }

    /// Fetches secrets for the selected environment if it is 1Password-backed
    /// (shelling out to `op`), showing the loading view while it runs. Local
    /// environments already have their secrets from the bulk load, so this is a
    /// no-op for them.
    private func loadSelectedEnvironmentSecrets() {
        guard let vaultId = selectedVaultId else { return }

        let env = selectedEnvironment
        guard
            let item = environmentItems.first(where: { $0.name == env }),
            item.isOnePassword
        else {
            isLoading = false
            return
        }

        opLoadToken += 1
        let token = opLoadToken
        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async {
            let resolved = Vault0Library.shared.listSecrets(vaultId: vaultId, environment: env)
            let own = resolved.filter { $0.environment.lowercased() == env.lowercased() }

            DispatchQueue.main.async {
                // Ignore stale results if the selection changed meanwhile.
                guard token == opLoadToken, selectedEnvironment == env else { return }
                secrets.removeAll { $0.environment.lowercased() == env.lowercased() }
                secrets.append(contentsOf: own)
                isLoading = false
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
    let environmentItems: [EnvironmentItem]
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
                ForEach(orderedEnvironments, id: \.self) { env in
                    SidebarEnvironmentButton(
                        title: env,
                        depth: depth(for: env),
                        isSelected: selectedEnvironment == env,
                        isOnePassword: isOnePassword(env),
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
                    environmentItems: environmentItems,
                    selectedEnvironment: $selectedEnvironment,
                    onChanged: onEnvironmentsChanged,
                )
            }
        }
    }

    /// Environments ordered as a tree: each parent immediately followed by its
    /// children (depth-first), so inherited environments nest under their parent.
    private var orderedEnvironments: [String] {
        guard !environmentItems.isEmpty else { return environments }

        let childrenByParent = Dictionary(grouping: environmentItems, by: { $0.parentId })
        var result: [String] = []

        func appendChildren(of parentId: String?) {
            let children = (childrenByParent[parentId] ?? [])
                .sorted { $0.displayOrder < $1.displayOrder }
            for child in children {
                result.append(child.name)
                appendChildren(of: child.id)
            }
        }

        appendChildren(of: nil)

        // Safety net: surface any environment not reached via the tree walk.
        for name in environments where !result.contains(name) {
            result.append(name)
        }
        return result
    }

    private func isOnePassword(_ name: String) -> Bool {
        environmentItems.first { $0.name == name }?.isOnePassword ?? false
    }

    private func depth(for name: String) -> Int {
        let byId = Dictionary(uniqueKeysWithValues: environmentItems.map { ($0.id, $0) })
        var current = environmentItems.first { $0.name == name }
        var depth = 0
        var guardCount = 0
        while let parentId = current?.parentId, let parent = byId[parentId], guardCount < environmentItems.count {
            depth += 1
            current = parent
            guardCount += 1
        }
        return depth
    }
}

struct SidebarEnvironmentButton: View {
    let title: String
    var depth: Int = 0
    let isSelected: Bool
    var isOnePassword: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isOnePassword {
                    Image("onepassword")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .help("Backed by 1Password")
                } else {
                    Image(systemName: depth > 0 ? "arrow.turn.down.right" : "server.rack")
                        .font(.system(size: 12))
                        .frame(width: 16)
                }
                Text(title)
                    .font(.system(size: 13))
                Spacer()
            }
            .padding(.leading, CGFloat(depth) * 14)
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
