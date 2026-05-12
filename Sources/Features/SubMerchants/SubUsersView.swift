import SwiftUI

/// Sub-users (cashiers / shop staff) for one sub-merchant. List + invite +
/// per-row edit / disable / re-issue-invite / clear-MFA. Parent-OWNER-only.
struct SubUsersView: View {
    let subID: String
    @EnvironmentObject private var repository: MerchantRepository
    @StateObject private var vm: SubUsersViewModel

    init(subID: String) {
        self.subID = subID
        _vm = StateObject(wrappedValue: SubUsersViewModel(subID: subID))
    }

    var body: some View {
        content
            .navigationTitle(LocalizedStringKey("subusers.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toast($vm.toast)
            .alert(item: $vm.error) { err in
                Alert(title: Text(err.title), message: Text(err.message), dismissButton: .default(Text(LocalizedStringKey("common.ok"))))
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { vm.startInvite() } label: { Image(systemName: "person.badge.plus") }
                        .accessibilityLabel(Text(LocalizedStringKey("subusers.invite")))
                }
            }
            .sheet(isPresented: $vm.showInvite) { inviteSheet }
            .sheet(item: $vm.inviteResult) { result in inviteLinkSheet(result) }
            .sheet(item: $vm.editUser) { _ in editSheet }
            .sheet(item: $vm.clearMfaUser) { _ in clearMfaSheet }
            .onAppear {
                vm.bind(repository: repository)
                vm.onAppear()
            }
    }

    @ViewBuilder private var content: some View {
        if vm.isLoading && vm.users.isEmpty {
            LoadingView(caption: NSLocalizedString("common.loading", value: "Loading…", comment: ""))
        } else if let error = vm.error, vm.users.isEmpty {
            ErrorStateView(error: error) { Task { await vm.load() } }
        } else if vm.users.isEmpty {
            EmptyStateView(
                title: NSLocalizedString("subusers.empty", value: "No users yet", comment: ""),
                systemImage: "person.2",
                description: nil,
                actionTitle: NSLocalizedString("subusers.invite", value: "Invite user", comment: ""),
                action: { vm.startInvite() })
        } else {
            List {
                ForEach(vm.users) { user in
                    SubUserRow(user: user)
                        .swipeActions(edge: .trailing) {
                            Button { vm.startEdit(user) } label: { Label(LocalizedStringKey("subusers.edit"), systemImage: "pencil") }
                                .tint(.blue)
                            if user.isActive {
                                Button(role: .destructive) { vm.disable(user) } label: { Label(LocalizedStringKey("subusers.disable"), systemImage: "person.crop.circle.badge.xmark") }
                            }
                        }
                        .contextMenu {
                            Button { vm.startEdit(user) } label: { Label(LocalizedStringKey("subusers.edit"), systemImage: "pencil") }
                            Button { vm.reissue(user) } label: { Label(LocalizedStringKey("subusers.reissue"), systemImage: "envelope.arrow.triangle.branch") }
                            if user.mfaEnabled {
                                Button { vm.startClearMfa(user) } label: { Label(LocalizedStringKey("subusers.clearMFA"), systemImage: "lock.open") }
                            }
                            if user.isActive {
                                Button(role: .destructive) { vm.disable(user) } label: { Label(LocalizedStringKey("subusers.disable"), systemImage: "person.crop.circle.badge.xmark") }
                            }
                        }
                }
            }
            .listStyle(.plain)
            .refreshable { await vm.load() }
        }
    }

    // MARK: - Invite sheet

    private var inviteSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(LocalizedStringKey("subusers.username"), text: $vm.inviteUsername)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField(LocalizedStringKey("subusers.fullName"), text: $vm.inviteFullName)
                        .textInputAutocapitalization(.words)
                }
                Section {
                    TextField(LocalizedStringKey("subusers.email"), text: $vm.inviteEmail)
                        .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField(LocalizedStringKey("subusers.mobile"), text: $vm.inviteMobile).keyboardType(.phonePad)
                    TextField(LocalizedStringKey("subusers.phone"), text: $vm.invitePhone).keyboardType(.phonePad)
                }
                Section {
                    Picker(LocalizedStringKey("subusers.role"), selection: $vm.inviteRole) {
                        ForEach(SubUserRole.allCases) { Text($0.label).tag($0) }
                    }
                }
                if let err = vm.inviteError {
                    Section { Text(err.message).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle(LocalizedStringKey("subusers.invite"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(LocalizedStringKey("common.cancel")) { vm.showInvite = false } }
                ToolbarItem(placement: .confirmationAction) {
                    if vm.isInviting { ProgressView() }
                    else { Button(LocalizedStringKey("subusers.invite")) { vm.submitInvite() }.disabled(!vm.canInvite) }
                }
            }
            .interactiveDismissDisabled(vm.isInviting)
        }
    }

    // MARK: - Invite-link result sheet

    private func inviteLinkSheet(_ result: SubUsersViewModel.InviteResult) -> some View {
        NavigationStack {
            Form {
                Section {
                    Text(result.url)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(4)
                } footer: {
                    if let channel = result.sentToChannel, !channel.isEmpty {
                        Text(String(format: NSLocalizedString("subusers.inviteSent", value: "Sent to %@", comment: ""), channel))
                    } else {
                        Text(LocalizedStringKey("subusers.inviteNotSent"))
                    }
                }
                Section {
                    if let url = URL(string: result.url) {
                        ShareLink(item: url) { Label(LocalizedStringKey("payLink.share"), systemImage: "square.and.arrow.up") }
                    }
                    Button {
                        UIPasteboard.general.string = result.url
                        vm.toast = Toast(message: NSLocalizedString("common.copied", value: "Copied", comment: ""))
                    } label: { Label(LocalizedStringKey("subusers.inviteCopy"), systemImage: "doc.on.doc") }
                }
            }
            .navigationTitle(LocalizedStringKey("subusers.inviteLinkTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(LocalizedStringKey("common.done")) { vm.inviteResult = nil } }
            }
        }
    }

    // MARK: - Edit sheet

    private var editSheet: some View {
        NavigationStack {
            Form {
                if let user = vm.editUser {
                    Section { LabeledContent(LocalizedStringKey("subusers.username"), value: user.username) }
                }
                Section {
                    Picker(LocalizedStringKey("subusers.role"), selection: $vm.editRole) {
                        ForEach(SubUserRole.allCases) { Text($0.label).tag($0) }
                    }
                    Toggle(LocalizedStringKey("subs.statusActive"), isOn: $vm.editActive)
                }
            }
            .navigationTitle(LocalizedStringKey("subusers.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(LocalizedStringKey("common.cancel")) { vm.editUser = nil } }
                ToolbarItem(placement: .confirmationAction) {
                    if vm.isEditing { ProgressView() }
                    else { Button(LocalizedStringKey("common.done")) { vm.submitEdit() } }
                }
            }
            .interactiveDismissDisabled(vm.isEditing)
        }
    }

    // MARK: - Clear-MFA sheet

    private var clearMfaSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(LocalizedStringKey("subusers.clearMFACode"), text: $vm.clearMfaCode)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: vm.clearMfaCode) { newValue in
                            vm.clearMfaCode = String(newValue.filter(\.isNumber).prefix(8))
                        }
                } footer: {
                    Text(LocalizedStringKey("account.mfa.intro"))
                }
            }
            .navigationTitle(LocalizedStringKey("subusers.clearMFA"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(LocalizedStringKey("common.cancel")) { vm.clearMfaUser = nil } }
                ToolbarItem(placement: .confirmationAction) {
                    if vm.isClearingMfa { ProgressView() }
                    else { Button(LocalizedStringKey("subusers.clearMFA")) { vm.submitClearMfa() }.disabled(!vm.canClearMfa) }
                }
            }
            .interactiveDismissDisabled(vm.isClearingMfa)
        }
    }
}

private struct SubUserRow: View {
    let user: SubUser

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(user.fullName.isEmpty ? user.username : user.fullName)
                    .font(.subheadline.weight(.medium)).lineLimit(1)
                Spacer(minLength: 6)
                if user.mfaEnabled {
                    Text("2FA")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .foregroundStyle(Color.green)
                        .background(Color.green.opacity(0.14), in: Capsule())
                }
                statusBadge
            }
            HStack(spacing: 8) {
                Text("@\(user.username)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                TagPill(text: SubUserRole.label(for: user.role), color: Brand.roleColor(for: user.role))
                Spacer(minLength: 4)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var statusBadge: some View {
        let active = user.isActive
        return Text(user.status.replacingOccurrences(of: "_", with: " "))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .foregroundStyle(active ? Color.green : Color.secondary)
            .background((active ? Color.green : Color.secondary).opacity(0.14), in: Capsule())
    }
}
