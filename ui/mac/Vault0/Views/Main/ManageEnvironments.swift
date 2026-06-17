import SwiftUI

struct ManageEnvironmentsDialog: View {
    @Environment(\.dismiss) var dismiss
    let vaultId: String
    let environments: [String]
    let environmentItems: [EnvironmentItem]
    @Binding var selectedEnvironment: String
    let onChanged: () -> Void

    @State private var validationError: String?
    @State private var showingAddSheet = false
    @State private var showingDeleteAlert = false
    @State private var environmentToDelete: String?
    @State private var cloningFrom: String?
    @State private var cloneNewName = ""
    @State private var cloneError: String?
    @State private var opConfigTarget: OpConfigTarget?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            if let source = cloningFrom {
                cloneForm(source: source)

                Divider()
                    .padding(.horizontal, 20)
            }

            environmentList
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 620, height: 520)
        .background(Color.vault0Background)
        .alert("Delete Environment", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let env = environmentToDelete {
                    deleteEnvironment(env)
                }
            }
        } message: {
            if let env = environmentToDelete {
                Text("Delete \"\(env)\"? Secrets in this environment will not be deleted.")
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddEnvironmentDialog(
                vaultId: vaultId,
                environments: environments,
                onCreated: onChanged,
            )
            .interactiveDismissDisabled(false)
        }
        .sheet(item: $opConfigTarget) { target in
            Configure1PasswordDialog(
                vaultId: vaultId,
                envName: target.id,
                currentVault: environmentItems.first(where: { $0.name == target.id })?.opVault,
                currentItem: environmentItems.first(where: { $0.name == target.id })?.opItem,
                onChanged: onChanged,
            )
        }
        .alert(
            "Couldn't update environment",
            isPresented: Binding(
                get: { validationError != nil },
                set: { if !$0 { validationError = nil } },
            ),
        ) {
            Button("OK", role: .cancel) { validationError = nil }
        } message: {
            Text(validationError ?? "")
        }
    }

    private var header: some View {
        HStack {
            Text("Manage Environments")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.vault0TextPrimary)
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.vault0TextSecondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.vault0Surface))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
    }

    private func cloneForm(source: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Clone \"\(source)\" as")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.vault0TextSecondary)

            HStack(spacing: 8) {
                TextField("New environment name", text: $cloneNewName)
                    .customTextField(isError: cloneError != nil)
                    .onSubmit(performClone)
                    .onChange(of: cloneNewName) { _ in cloneError = nil }

                Button(action: performClone) {
                    Text("Clone")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(cloneNewName.trimmingCharacters(in: .whitespaces).isEmpty ? Color.vault0TextTertiary : Color.vault0Accent)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(cloneNewName.trimmingCharacters(in: .whitespaces).isEmpty)

                Button(action: {
                    cloningFrom = nil
                    cloneNewName = ""
                    cloneError = nil
                }) {
                    Text("Cancel")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.vault0TextSecondary)
                }
                .buttonStyle(.plain)
            }

            if let error = cloneError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 11))
                    Text(error)
                        .font(.system(size: 11))
                }
                .foregroundColor(.vault0Error)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    private var environmentList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Environments")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.vault0TextSecondary)

                Spacer()

                Button(action: { showingAddSheet = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Add")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.vault0Accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
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
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            if environments.isEmpty {
                Text("No environments")
                    .font(.system(size: 13))
                    .foregroundColor(.vault0TextTertiary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)

                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(environments, id: \.self) { env in
                            EnvironmentManageRow(
                                env: env,
                                parentName: parentName(of: env),
                                parentCandidates: environments.filter { $0 != env },
                                canDelete: environments.count > 1,
                                isOnePassword: isOnePassword(env),
                                onSetParent: { setParent(of: env, to: $0) },
                                onClone: {
                                    cloningFrom = env
                                    cloneNewName = "\(env)-copy"
                                    cloneError = nil
                                    validationError = nil
                                },
                                onDelete: {
                                    environmentToDelete = env
                                    showingDeleteAlert = true
                                },
                                onConfigureOnePassword: {
                                    opConfigTarget = OpConfigTarget(id: env)
                                },
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
        }
    }

    private func isOnePassword(_ env: String) -> Bool {
        environmentItems.first(where: { $0.name == env })?.isOnePassword ?? false
    }

    private func parentName(of env: String) -> String? {
        guard let item = environmentItems.first(where: { $0.name == env }),
              let parentId = item.parentId
        else {
            return nil
        }
        return environmentItems.first(where: { $0.id == parentId })?.name
    }

    private func setParent(of env: String, to parent: String?) {
        if Vault0Library.shared.setEnvironmentParent(vaultId: vaultId, name: env, parent: parent) {
            validationError = nil
            onChanged()
        } else {
            validationError = parent == nil
                ? "Failed to clear parent"
                : "Couldn't set parent (would it create a cycle?)"
        }
    }

    private func performClone() {
        guard let source = cloningFrom else { return }
        let trimmed = cloneNewName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        if trimmed.contains(" ") {
            cloneError = "No spaces allowed"
            return
        }

        if environments.contains(trimmed.lowercased()) {
            cloneError = "Already exists"
            return
        }

        if Vault0Library.shared.cloneEnvironment(vaultId: vaultId, sourceName: source, newName: trimmed) {
            cloningFrom = nil
            cloneNewName = ""
            cloneError = nil
            onChanged()
        } else {
            cloneError = "Failed to clone"
        }
    }

    private func deleteEnvironment(_ env: String) {
        if Vault0Library.shared.deleteEnvironment(vaultId: vaultId, name: env) {
            // If we deleted the selected environment, select another one
            if selectedEnvironment == env {
                if let firstRemaining = environments.first(where: { $0 != env }) {
                    selectedEnvironment = firstRemaining
                }
            }
            onChanged()
        }
    }
}

struct AddEnvironmentDialog: View {
    @Environment(\.dismiss) var dismiss
    let vaultId: String
    let environments: [String]
    var defaultParent: String?
    let onCreated: () -> Void

    @State private var name = ""
    @State private var parent: String?
    @State private var error: String?

    init(vaultId: String, environments: [String], defaultParent: String? = nil, onCreated: @escaping () -> Void) {
        self.vaultId = vaultId
        self.environments = environments
        self.defaultParent = defaultParent
        self.onCreated = onCreated
        _parent = State(initialValue: defaultParent)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
                .background(Color.vault0Border)
            fields
            Spacer()
            Divider()
                .background(Color.vault0Border)
            footer
        }
        .frame(width: 480, height: 360)
        .background(Color.vault0Background)
    }

    private var header: some View {
        HStack {
            Text("Add Environment")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.vault0TextPrimary)
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.vault0TextSecondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.vault0Surface))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Name")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.vault0TextSecondary)

                TextField("e.g., staging", text: $name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .customTextField(isError: error != nil)
                    .onSubmit(create)
                    .onChange(of: name) { _ in error = nil }

                if let error {
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
                Text("Inherits from")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.vault0TextSecondary)

                Menu {
                    Button("None") { parent = nil }
                    ForEach(environments, id: \.self) { env in
                        Button(env) { parent = env }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(parent ?? "None")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.vault0TextPrimary)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10))
                            .foregroundColor(.vault0TextSecondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.vault0Surface)
                    .cornerRadius(8)
                }
                .menuStyle(.borderlessButton)

                Text("Secrets not set here are inherited from the parent environment.")
                    .font(.system(size: 11))
                    .foregroundColor(.vault0TextTertiary)
            }
        }
        .padding(20)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(SecondaryButtonStyle())
                .frame(width: 100)

            Button("Create") { create() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .frame(width: 100)
        }
        .padding(20)
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        if trimmed.contains(" ") {
            error = "No spaces allowed"
            return
        }

        if environments.contains(trimmed.lowercased()) {
            error = "Already exists"
            return
        }

        if Vault0Library.shared.createEnvironment(vaultId: vaultId, name: trimmed, parent: parent) {
            onCreated()
            dismiss()
        } else {
            error = "Failed to create"
        }
    }
}

struct OpConfigTarget: Identifiable {
    let id: String // environment name
}

/// Searchable dropdown for picking a 1Password vault or item. Shows a search
/// field and a scrollable, filterable list in a popover.
struct OpPicker: View {
    let title: String
    let placeholder: String
    let options: [OpEntry]
    @Binding var selectedId: String?
    var onChange: () -> Void

    @State private var isOpen = false
    @State private var query = ""
    @State private var hoveredId: String?
    @State private var triggerHeight: CGFloat = 0
    @FocusState private var searchFocused: Bool

    private var selectedName: String? {
        options.first(where: { $0.id == selectedId })?.name
    }

    private var filtered: [OpEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return options }
        return options.filter { $0.name.lowercased().contains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.vault0TextSecondary)

            Button(action: { isOpen.toggle() }) {
                HStack(spacing: 6) {
                    Text(selectedName ?? placeholder)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(selectedName == nil ? .vault0TextTertiary : .vault0TextPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.vault0TextSecondary)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                        .animation(.easeInOut(duration: 0.15), value: isOpen)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(Color.vault0Surface)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isOpen ? Color.vault0Accent : Color.vault0Border, lineWidth: 1),
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { triggerHeight = proxy.size.height }
                        .onChange(of: proxy.size.height) { triggerHeight = $0 }
                },
            )
            .overlay(alignment: .topLeading) {
                if isOpen {
                    dropdownList
                        .offset(y: triggerHeight + 6)
                }
            }
        }
        .zIndex(isOpen ? 10 : 0)
    }

    private var dropdownList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(.vault0TextTertiary)
                TextField("Search", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($searchFocused)
                if !query.isEmpty {
                    Button(action: { query = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.vault0TextTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider().background(Color.vault0Border)

            ScrollView {
                VStack(spacing: 2) {
                    if filtered.isEmpty {
                        Text("No matches")
                            .font(.system(size: 12))
                            .foregroundColor(.vault0TextTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(filtered) { option in
                            row(option)
                        }
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: 220)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.vault0Surface)
                .shadow(color: Color.black.opacity(0.22), radius: 16, x: 0, y: 8),
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.vault0Border, lineWidth: 1),
        )
        .onAppear { searchFocused = true }
    }

    private func row(_ option: OpEntry) -> some View {
        let isSelected = option.id == selectedId
        let isHovered = option.id == hoveredId

        return Button(action: { select(option) }) {
            HStack(spacing: 8) {
                Text(option.name)
                    .font(.system(size: 13))
                    .foregroundColor(.vault0TextPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.vault0Accent)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        isSelected
                            ? Color.vault0Accent.opacity(0.12)
                            : (isHovered ? Color.vault0Accent.opacity(0.06) : Color.clear),
                    ),
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredId = hovering ? option.id : (hoveredId == option.id ? nil : hoveredId)
        }
    }

    private func select(_ option: OpEntry) {
        selectedId = option.id
        isOpen = false
        query = ""
        onChange()
    }
}

struct Configure1PasswordDialog: View {
    @Environment(\.dismiss) var dismiss
    let vaultId: String
    let envName: String
    let currentVault: String?
    let currentItem: String?
    let onChanged: () -> Void

    @State private var token = ""
    @State private var vaults: [OpEntry] = []
    @State private var selectedVaultId: String?
    @State private var items: [OpEntry] = []
    @State private var selectedItemId: String?
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var error: String?

    private var isEditing: Bool {
        currentItem != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.vault0Border)
            fields
            Spacer()
            Divider().background(Color.vault0Border)
            footer
        }
        .frame(width: 480, height: 560)
        .background(Color.vault0Background)
        .onAppear {
            selectedVaultId = currentVault
            selectedItemId = currentItem
        }
    }

    private var header: some View {
        HStack {
            Text(isEditing ? "Edit 1Password backing" : "Back with 1Password")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.vault0TextPrimary)
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.vault0TextSecondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.vault0Surface))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Environment \"\(envName)\" will read and write its secrets from a single 1Password item. Existing local secrets are pushed to the item, then removed from vault0.")
                .font(.system(size: 11))
                .foregroundColor(.vault0TextTertiary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Service account token")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.vault0TextSecondary)
                HStack(spacing: 8) {
                    SecureField("ops_...", text: $token)
                        .customTextField(isError: false)
                        .onChange(of: token) { _ in error = nil }
                    Button(action: loadVaults) {
                        Text("Connect")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(token.trimmingCharacters(in: .whitespaces).isEmpty ? Color.vault0TextTertiary : Color.vault0Accent)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
                }
            }

            if !vaults.isEmpty {
                OpPicker(
                    title: "1Password vault",
                    placeholder: "Select a vault",
                    options: vaults,
                    selectedId: $selectedVaultId,
                ) {
                    items = []
                    selectedItemId = nil
                    loadItems()
                }
            }

            if !items.isEmpty {
                OpPicker(
                    title: "1Password item",
                    placeholder: "Select an item",
                    options: items,
                    selectedId: $selectedItemId,
                    onChange: {},
                )
            }

            if isLoading {
                ProgressView().controlSize(.small)
            }

            if let error {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill").font(.system(size: 11))
                    Text(error).font(.system(size: 11))
                }
                .foregroundColor(.vault0Error)
            }
        }
        .padding(20)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(SecondaryButtonStyle())
                .frame(width: 100)
            Button(isSaving ? "Saving..." : "Save") { save() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canSave || isSaving)
                .frame(width: 100)
        }
        .padding(20)
    }

    private var canSave: Bool {
        !token.trimmingCharacters(in: .whitespaces).isEmpty
            && selectedVaultId != nil
            && selectedItemId != nil
    }

    private func loadVaults() {
        let tk = token.trimmingCharacters(in: .whitespaces)
        guard !tk.isEmpty else { return }
        isLoading = true
        error = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Vault0Library.shared.opListVaults(token: tk)
            DispatchQueue.main.async {
                isLoading = false
                if result.isEmpty {
                    error = "No vaults found. Check the token and the op CLI."
                }
                vaults = result
                if selectedVaultId != nil { loadItems() }
            }
        }
    }

    private func loadItems() {
        let tk = token.trimmingCharacters(in: .whitespaces)
        guard let vault = selectedVaultId, !tk.isEmpty else { return }
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Vault0Library.shared.opListItems(token: tk, vault: vault)
            DispatchQueue.main.async {
                isLoading = false
                items = result
                if result.isEmpty {
                    error = "No items found in that vault."
                }
            }
        }
    }

    private func save() {
        let tk = token.trimmingCharacters(in: .whitespaces)
        guard let vault = selectedVaultId, let item = selectedItemId else { return }
        isSaving = true
        error = nil
        let editing = isEditing
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = editing
                ? Vault0Library.shared.updateOpEnvironment(
                    vaultId: vaultId, envName: envName, token: tk, opVault: vault, opItem: item,
                )
                : Vault0Library.shared.configureOpEnvironment(
                    vaultId: vaultId, envName: envName, token: tk, opVault: vault, opItem: item,
                )
            DispatchQueue.main.async {
                isSaving = false
                if ok {
                    onChanged()
                    dismiss()
                } else {
                    error = "Failed to configure 1Password. Check the token, vault, and item."
                }
            }
        }
    }
}

struct EnvironmentManageRow: View {
    let env: String
    let parentName: String?
    let parentCandidates: [String]
    let canDelete: Bool
    let isOnePassword: Bool
    let onSetParent: (String?) -> Void
    let onClone: () -> Void
    let onDelete: () -> Void
    let onConfigureOnePassword: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "server.rack")
                .font(.system(size: 12))
                .foregroundColor(.vault0Accent)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(env)
                    .font(.system(size: 13))
                    .foregroundColor(.vault0TextPrimary)
                if let parentName {
                    Text("inherits from \(parentName)")
                        .font(.system(size: 10))
                        .foregroundColor(.vault0TextTertiary)
                }
            }

            if isOnePassword {
                Text("1Password")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.vault0Accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.vault0Accent.opacity(0.1)),
                    )
            }

            Spacer()

            Button(action: onConfigureOnePassword) {
                Image("onepassword")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 15, height: 15)
                    .grayscale(isOnePassword ? 0 : 1)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help(isOnePassword ? "Edit 1Password backing" : "Back this environment with 1Password")

            Menu {
                Button("No parent") { onSetParent(nil) }
                ForEach(parentCandidates, id: \.self) { candidate in
                    Button(candidate) { onSetParent(candidate) }
                }
            } label: {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 12))
                    .foregroundColor(.vault0TextSecondary)
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Set parent environment")

            Button(action: onClone) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 12))
                    .foregroundColor(.vault0TextSecondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)

            if canDelete {
                TrashButton(action: onDelete)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(Color.vault0Surface)
        .cornerRadius(6)
    }
}
