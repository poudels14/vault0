import SwiftUI

struct ManageEnvironmentsDialog: View {
    @Environment(\.dismiss) var dismiss
    let vaultId: String
    let environments: [String]
    let environmentItems: [EnvironmentItem]
    @Binding var selectedEnvironment: String
    let onChanged: () -> Void

    @State private var newEnvironmentName = ""
    @State private var newEnvironmentParent: String?
    @State private var validationError: String?
    @State private var showingDeleteAlert = false
    @State private var environmentToDelete: String?
    @State private var cloningFrom: String?
    @State private var cloneNewName = ""
    @State private var cloneError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                        .background(
                            Circle()
                                .fill(Color.vault0Surface),
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            if let source = cloningFrom {
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
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Add Environment")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.vault0TextSecondary)

                    HStack(spacing: 8) {
                        TextField("e.g., staging", text: $newEnvironmentName)
                            .customTextField(isError: validationError != nil)
                            .onSubmit(addEnvironment)
                            .onChange(of: newEnvironmentName) { _ in
                                validationError = nil
                            }

                        Button(action: addEnvironment) {
                            Text("Add")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(newEnvironmentName.trimmingCharacters(in: .whitespaces).isEmpty ? Color.vault0TextTertiary : Color.vault0Accent)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .disabled(newEnvironmentName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    HStack(spacing: 8) {
                        Text("Inherits from")
                            .font(.system(size: 12))
                            .foregroundColor(.vault0TextSecondary)

                        Menu {
                            Button("None") { newEnvironmentParent = nil }
                            ForEach(environments, id: \.self) { env in
                                Button(env) { newEnvironmentParent = env }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(newEnvironmentParent ?? "None")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.vault0TextPrimary)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 9))
                                    .foregroundColor(.vault0TextSecondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.vault0Surface)
                            .cornerRadius(6)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }

                    if let error = validationError {
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

            Divider()
                .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 8) {
                Text("Environments")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.vault0TextSecondary)
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
                                HStack {
                                    Image(systemName: "server.rack")
                                        .font(.system(size: 12))
                                        .foregroundColor(.vault0Accent)
                                        .frame(width: 20)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(env)
                                            .font(.system(size: 13))
                                            .foregroundColor(.vault0TextPrimary)
                                        if let parent = parentName(of: env) {
                                            Text("inherits from \(parent)")
                                                .font(.system(size: 10))
                                                .foregroundColor(.vault0TextTertiary)
                                        }
                                    }

                                    Spacer()

                                    Menu {
                                        Button("No parent") { setParent(of: env, to: nil) }
                                        ForEach(environments.filter { $0 != env }, id: \.self) { candidate in
                                            Button(candidate) { setParent(of: env, to: candidate) }
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

                                    Button(action: {
                                        cloningFrom = env
                                        cloneNewName = "\(env)-copy"
                                        cloneError = nil
                                        validationError = nil
                                    }) {
                                        Image(systemName: "doc.on.doc")
                                            .font(.system(size: 12))
                                            .foregroundColor(.vault0TextSecondary)
                                            .frame(width: 24, height: 24)
                                    }
                                    .buttonStyle(.plain)

                                    if environments.count > 1 {
                                        TrashButton {
                                            environmentToDelete = env
                                            showingDeleteAlert = true
                                        }
                                    }
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 8)
                                .background(Color.vault0Surface)
                                .cornerRadius(6)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 500, height: 360)
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
    }

    private func addEnvironment() {
        let trimmed = newEnvironmentName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        if trimmed.contains(" ") {
            validationError = "No spaces allowed"
            return
        }

        if environments.contains(trimmed.lowercased()) {
            validationError = "Already exists"
            return
        }

        if Vault0Library.shared.createEnvironment(vaultId: vaultId, name: trimmed, parent: newEnvironmentParent) {
            newEnvironmentName = ""
            newEnvironmentParent = nil
            validationError = nil
            onChanged()
        } else {
            validationError = "Failed to create"
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
