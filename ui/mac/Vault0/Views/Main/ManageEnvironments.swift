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
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
        }
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

struct EnvironmentManageRow: View {
    let env: String
    let parentName: String?
    let parentCandidates: [String]
    let canDelete: Bool
    let onSetParent: (String?) -> Void
    let onClone: () -> Void
    let onDelete: () -> Void

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

            Spacer()

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
