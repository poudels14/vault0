import SwiftUI

struct SecretsListView: View {
    let vaultId: String?
    let selectedEnvironment: String
    let environments: [String]
    @Binding var secrets: [Secret]
    @Binding var isLoading: Bool
    var onRefresh: (() -> Void)?

    @State private var searchText: String = ""
    @State private var addSecretData: AddSecretData? = nil
    @State private var visibleSecretId: String? = nil
    @State private var hideTimer: Timer? = nil

    struct AddSecretData: Identifiable {
        let id = UUID()
        let environment: String
        let key: String?
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                SearchField(text: $searchText, placeholder: "Search secrets...")

                Button(action: {
                    addSecretData = AddSecretData(environment: selectedEnvironment, key: nil)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Add Secret")
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
                .disabled(vaultId == nil)
                .opacity(vaultId == nil ? 0.5 : 1.0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.vault0Background)

            Divider()
                .background(Color.vault0Border)

            if isLoading {
                loadingView
            } else if vaultId == nil {
                emptyVaultView
            } else if secrets.isEmpty {
                emptySecretsView
            } else {
                secretsListContent
            }
        }
        .background(Color.vault0Background)
        .sheet(item: $addSecretData) { data in
            if let vaultId {
                AddSecretDialog(
                    vaultId: vaultId,
                    defaultEnvironment: data.environment,
                    defaultKey: data.key,
                    existingSecrets: secrets,
                    onSave: handleSaveSecret,
                )
                .interactiveDismissDisabled(false)
            }
        }
        .onChange(of: selectedEnvironment) { _ in
            hideTimer?.invalidate()
            hideTimer = nil
            visibleSecretId = nil
        }
        .onChange(of: searchText) { _ in
            hideTimer?.invalidate()
            hideTimer = nil
            visibleSecretId = nil
        }
        .onDisappear {
            hideTimer?.invalidate()
            hideTimer = nil
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Loading secrets...")
                .font(.system(size: 13))
                .foregroundColor(.vault0TextSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.vault0Background)
    }

    private var emptyVaultView: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(.vault0TextTertiary)
            Text("No Vault Selected")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.vault0TextPrimary)
            Text("Select a vault from the sidebar to view secrets")
                .font(.system(size: 13))
                .foregroundColor(.vault0TextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.vault0Background)
    }

    private var emptySecretsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "key")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(.vault0TextTertiary)
            Text("No Secrets Yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.vault0TextPrimary)
            Text("Add your first secret to get started")
                .font(.system(size: 13))
                .foregroundColor(.vault0TextSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.vault0Background)
    }

    private var secretsListContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(displayedSecretKeys.enumerated()), id: \.element) { index, key in
                    if let secret = secretsForEnvironment[key] {
                        SecretRow(
                            secret: secret,
                            isVisible: visibleSecretId == secret.id,
                            onToggleVisibility: {
                                toggleSecretVisibility(secretId: secret.id)
                            },
                            onDelete: {
                                deleteSecret(secret)
                            },
                            onEdit: { newValue in
                                updateSecret(secret, newValue: newValue)
                            },
                        )
                    } else {
                        MissingSecretRow(
                            key: key,
                            environment: selectedEnvironment,
                            onAdd: {
                                addSecretData = AddSecretData(environment: selectedEnvironment, key: key)
                            },
                        )
                    }

                    if index < displayedSecretKeys.count - 1 {
                        Divider()
                            .padding(.horizontal, 20)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .background(Color.vault0Background)
        .id("\(selectedEnvironment)-\(searchText)")
    }

    private var allSecretKeys: Set<String> {
        Set(secrets
            .filter { environments.contains($0.environment.lowercased()) }
            .map(\.key))
    }

    private var secretsForEnvironment: [String: Secret] {
        let envSecrets = secrets.filter { $0.environment.lowercased() == selectedEnvironment.lowercased() }
        return Dictionary(uniqueKeysWithValues: envSecrets.map { ($0.key, $0) })
    }

    private var displayedSecretKeys: [String] {
        let keys = Array(allSecretKeys)
        let filtered = searchText.isEmpty ? keys : keys.filter { key in
            key.localizedCaseInsensitiveContains(searchText)
        }
        return filtered.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func handleSaveSecret(vaultId: String, environment: String, key: String, value: String) {
        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async {
            let success = Vault0Library.shared.createSecret(
                vaultId: vaultId,
                environment: environment,
                key: key,
                value: value,
            )

            DispatchQueue.main.async {
                if success {
                    NSLog("Secret created successfully")
                    onRefresh?()
                } else {
                    NSLog("Failed to create secret")
                    isLoading = false
                }
            }
        }
    }

    private func toggleSecretVisibility(secretId: String) {
        hideTimer?.invalidate()
        hideTimer = nil

        if visibleSecretId == secretId {
            visibleSecretId = nil
        } else {
            visibleSecretId = secretId
            hideTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: false) { _ in
                visibleSecretId = nil
                hideTimer = nil
            }
        }
    }

    private func deleteSecret(_ secret: Secret) {
        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async {
            let success = Vault0Library.shared.deleteSecret(id: secret.id)

            DispatchQueue.main.async {
                if success {
                    NSLog("Secret deleted successfully")
                    onRefresh?()
                } else {
                    NSLog("Failed to delete secret")
                    isLoading = false
                }
            }
        }
    }

    private func updateSecret(_ secret: Secret, newValue: String) {
        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async {
            let success = Vault0Library.shared.updateSecret(
                id: secret.id,
                value: newValue,
            )

            DispatchQueue.main.async {
                if success {
                    NSLog("Secret updated successfully")
                    onRefresh?()
                } else {
                    NSLog("Failed to update secret")
                    isLoading = false
                }
            }
        }
    }
}

struct SecretRow: View {
    let secret: Secret
    let isVisible: Bool
    let onToggleVisibility: () -> Void
    let onDelete: () -> Void
    let onEdit: (String) -> Void

    @State private var showingDeleteAlert = false
    @State private var showingEditSheet = false
    @State private var clipboardTimer: Timer? = nil
    @State private var copiedValue: String? = nil
    @State private var isHovering = false
    @State private var showCopiedFeedback = false
    @State private var showKeyCopiedFeedback = false

    private func formattedUpdatedDate(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        let minutes = Int(interval / 60)
        let hours = Int(interval / 3600)
        let days = Int(interval / 86400)

        if minutes < 1 {
            return "Updated just now"
        } else if minutes < 60 {
            return "Updated \(minutes)m ago"
        } else if hours < 24 {
            return "Updated \(hours)h ago"
        } else if days < 30 {
            return "Updated \(days)d ago"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return "Updated \(formatter.string(from: date))"
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.vault0Success)
                        .frame(width: 6, height: 6)
                    Text(secret.key)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.vault0TextPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)

                    Button(action: { copyKeyToClipboard(secret.key) }) {
                        Image(systemName: showKeyCopiedFeedback ? "checkmark" : "square.on.square")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(showKeyCopiedFeedback ? .vault0Success : .vault0TextTertiary)
                            .frame(width: 18, height: 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Copy key")
                    .opacity(isHovering ? 1 : 0)
                    .allowsHitTesting(isHovering)
                }

                Text(formattedUpdatedDate(secret.updatedDate))
                    .font(.system(size: 11, weight: .light))
                    .foregroundColor(.vault0TextTertiary)
                    .padding(.leading, 14)
            }
            .frame(minWidth: 180, alignment: .leading)

            Group {
                if isVisible {
                    Text(secret.value)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.vault0TextSecondary)
                } else {
                    Text(String(repeating: "•", count: 18))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.vault0TextTertiary)
                }
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 0) {
                if isHovering || isVisible {
                    ActionButton(
                        icon: isVisible ? "eye.slash" : "eye",
                        action: onToggleVisibility,
                    )
                    .help(isVisible ? "Hide value" : "Show value")

                    ActionButton(
                        icon: showCopiedFeedback ? "checkmark" : "square.on.square",
                        action: { copyToClipboard(secret.value) },
                        color: showCopiedFeedback ? .vault0Success : .vault0TextTertiary,
                        hoverColor: showCopiedFeedback ? .vault0Success : .vault0TextPrimary,
                    )
                    .help("Copy to clipboard")

                    ActionButton(
                        icon: "square.and.pencil",
                        action: { showingEditSheet = true },
                    )
                    .help("Edit secret")

                    ActionButton(
                        icon: "trash",
                        action: { showingDeleteAlert = true },
                        hoverColor: .vault0Error,
                    )
                    .help("Delete secret")
                }
            }
            .frame(width: 112)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(isHovering ? Color.vault0Surface.opacity(0.5) : Color.clear)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
        .alert("Delete Secret", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive, action: onDelete)
        } message: {
            Text("Are you sure you want to delete \"\(secret.key)\"? This action cannot be undone.")
        }
        .sheet(isPresented: $showingEditSheet) {
            EditSecretSheet(
                secretKey: secret.key,
                currentValue: secret.value,
                onSave: { newValue in
                    onEdit(newValue)
                },
            )
        }
        .onDisappear {
            clipboardTimer?.invalidate()
            clipboardTimer = nil
        }
    }

    private func copyKeyToClipboard(_ key: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(key, forType: .string)

        withAnimation {
            showKeyCopiedFeedback = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showKeyCopiedFeedback = false
            }
        }
    }

    private func copyToClipboard(_ text: String) {
        clipboardTimer?.invalidate()
        clipboardTimer = nil

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedValue = text

        withAnimation {
            showCopiedFeedback = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showCopiedFeedback = false
            }
        }

        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { _ in
            if let clipboardString = NSPasteboard.general.string(forType: .string),
               clipboardString == copiedValue
            {
                NSPasteboard.general.clearContents()
            }
            clipboardTimer = nil
            copiedValue = nil
        }
    }
}

struct MissingSecretRow: View {
    let key: String
    let environment: String
    let onAdd: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.vault0Warning)
                        .frame(width: 6, height: 6)
                    Text(key)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.vault0TextPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Text("Missing in \(environment)")
                    .font(.system(size: 11))
                    .foregroundColor(.vault0Warning)
                    .padding(.leading, 14)
            }
            .frame(minWidth: 180, alignment: .leading)

            Spacer()

            Button(action: onAdd) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .medium))
                    Text("Add")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.vault0TextSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.vault0Surface),
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.vault0Border, lineWidth: 1),
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(isHovering ? Color.vault0Surface.opacity(0.5) : Color.clear)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }
}

struct EditSecretSheet: View {
    let secretKey: String
    let currentValue: String
    let onSave: (String) -> Void

    @State private var value: String
    @State private var showValue: Bool = false
    @Environment(\.dismiss) var dismiss

    private var maskedPreviewText: String {
        if value.isEmpty {
            return "Enter value"
        }
        let bulletCount = min(max(value.count, 24), 240)
        return String(repeating: "•", count: bulletCount)
    }

    init(secretKey: String, currentValue: String, onSave: @escaping (String) -> Void) {
        self.secretKey = secretKey
        self.currentValue = currentValue
        self.onSave = onSave
        _value = State(initialValue: currentValue)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit Secret")
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
                    Text(secretKey)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.vault0TextPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.vault0Surface)
                        .cornerRadius(8)
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
                                Text(maskedPreviewText)
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundColor(value.isEmpty ? .vault0TextTertiary : .vault0TextSecondary)
                                    .lineLimit(4)
                                    .truncationMode(.tail)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .frame(height: 96)
                                    .background(Color.vault0Background)
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.vault0Border, lineWidth: 1),
                                    )
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
                    onSave(value)
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(value.isEmpty || value == currentValue)
                .frame(width: 100)
            }
            .padding(20)
        }
        .frame(width: 480, height: 420)
        .background(Color.vault0Background)
    }
}
