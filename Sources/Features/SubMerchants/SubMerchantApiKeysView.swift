import SwiftUI
import Payhub

/// Sub-merchant API keys: list (masked) + mint + revoke. The plaintext
/// `secret` returned by `POST /merchant/sub-merchants/{sid}/api-keys` is
/// shown **once** in a separate reveal sheet — the user copies it or it's
/// gone (the server stores only an argon2 hash). Mirrors the Android
/// `SubMerchantApiKeysScreen`.
struct SubMerchantApiKeysView: View {
    let subID: String
    @EnvironmentObject private var repository: MerchantRepository
    @StateObject private var vm: SubMerchantApiKeysViewModel

    init(subID: String) {
        self.subID = subID
        _vm = StateObject(wrappedValue: SubMerchantApiKeysViewModel(subID: subID))
    }

    var body: some View {
        content
            .navigationTitle(LocalizedStringKey("sub.apiKeys.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toast($vm.toast)
            .alert(item: $vm.error) { err in
                Alert(title: Text(err.title), message: Text(err.message),
                      dismissButton: .default(Text(LocalizedStringKey("common.ok"))))
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { vm.startCreate() } label: { Image(systemName: "plus") }
                        .accessibilityLabel(Text(LocalizedStringKey("sub.apiKeys.create")))
                }
            }
            .sheet(isPresented: $vm.showCreate) { createSheet }
            // The reveal sheet is a **separate** presentation from the create
            // sheet so the user explicitly transitions create → reveal and
            // dismissing the reveal can't accidentally pop the create form
            // back into view with stale state.
            .sheet(item: $vm.revealedKey, onDismiss: { vm.dismissReveal() }) { reveal in
                revealSheet(reveal)
            }
            .onAppear {
                vm.bind(repository: repository)
                vm.onAppear()
            }
    }

    @ViewBuilder private var content: some View {
        if vm.isLoading && vm.keys.isEmpty {
            LoadingView(caption: NSLocalizedString("common.loading", value: "Loading…", comment: ""))
        } else if let error = vm.error, vm.keys.isEmpty {
            ErrorStateView(error: error) { Task { await vm.load() } }
        } else if vm.keys.isEmpty {
            EmptyStateView(
                title: NSLocalizedString("sub.apiKeys.empty", value: "No API keys yet", comment: ""),
                systemImage: "key.horizontal",
                description: NSLocalizedString("sub.apiKeys.empty.body", value: "", comment: ""),
                actionTitle: NSLocalizedString("sub.apiKeys.create", value: "Create API key", comment: ""),
                action: { vm.startCreate() })
        } else {
            List {
                ForEach(vm.keys) { key in row(key) }
            }
            .listStyle(.plain)
            .refreshable { await vm.load() }
        }
    }

    @ViewBuilder private func row(_ key: MerchantApiKey) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(key.keyId).font(.system(.subheadline, design: .monospaced)).lineLimit(1)
                Spacer(minLength: 8)
                if key.status == "revoked" {
                    TagPill(text: NSLocalizedString("sub.apiKeys.revoked", value: "Revoked", comment: ""), color: .secondary)
                } else {
                    TagPill(text: NSLocalizedString("sub.apiKeys.active", value: "Active", comment: ""), color: .green)
                }
            }
            HStack(spacing: 6) {
                ForEach(key.scopes, id: \.self) { scope in
                    Text(scope).font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.14), in: Capsule())
                }
            }
            HStack(spacing: 10) {
                if let last = key.lastUsedAt, let date = ISO.date(from: last) {
                    Text(String(format: NSLocalizedString("sub.apiKeys.lastUsed", value: "Last used %@", comment: ""),
                                date.formatted(date: .abbreviated, time: .shortened)))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(NSLocalizedString("sub.apiKeys.never", value: "Never used", comment: ""))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if let created = ISO.date(from: key.createdAt) {
                    Text(created.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing) {
            if key.status != "revoked" {
                Button(role: .destructive) {
                    vm.revoke(key)
                } label: {
                    Label(LocalizedStringKey("sub.apiKeys.revoke"), systemImage: "xmark.circle")
                }
            }
        }
    }

    // MARK: - Create sheet

    private var createSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(LocalizedStringKey("sub.apiKeys.scopes"),
                              text: $vm.createScopesText, axis: .vertical)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section {
                    TextField(LocalizedStringKey("sub.apiKeys.allowedIps"),
                              text: $vm.createAllowedIpsText, axis: .vertical)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                } footer: {
                    Text(LocalizedStringKey("sub.apiKeys.allowedIps.hint"))
                }
                Section {
                    Picker(LocalizedStringKey("sub.apiKeys.rateLimitTier"),
                           selection: $vm.createRateLimitTier) {
                        Text("standard").tag("standard")
                        Text("premium").tag("premium")
                    }
                }
            }
            .navigationTitle(LocalizedStringKey("sub.apiKeys.create"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LocalizedStringKey("common.cancel")) { vm.showCreate = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if vm.isCreating { ProgressView() }
                    else {
                        Button(LocalizedStringKey("sub.apiKeys.create")) { vm.submitCreate() }
                            .disabled(!vm.canCreate)
                    }
                }
            }
            .interactiveDismissDisabled(vm.isCreating)
        }
    }

    // MARK: - Reveal sheet

    private func revealSheet(_ reveal: SubMerchantApiKeysViewModel.RevealedKey) -> some View {
        NavigationStack {
            Form {
                Section {
                    Text(reveal.wireFormat)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(nil)
                } header: {
                    Text(LocalizedStringKey("sub.apiKeys.reveal.title"))
                } footer: {
                    Text(LocalizedStringKey("sub.apiKeys.reveal.body"))
                }
                Section {
                    Button {
                        UIPasteboard.general.string = reveal.wireFormat
                        vm.toast = Toast(message: NSLocalizedString(
                            "common.copied", value: "Copied", comment: ""))
                    } label: {
                        Label(LocalizedStringKey("sub.apiKeys.reveal.copy"), systemImage: "doc.on.doc")
                    }
                }
            }
            .navigationTitle(LocalizedStringKey("sub.apiKeys.title"))
            .navigationBarTitleDisplayMode(.inline)
            // Interactive dismiss disabled so the user must explicitly tap
            // "I've saved it" — the secret won't be retrievable later.
            .interactiveDismissDisabled(true)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(LocalizedStringKey("sub.apiKeys.reveal.done")) { vm.dismissReveal() }
                }
            }
        }
    }
}
