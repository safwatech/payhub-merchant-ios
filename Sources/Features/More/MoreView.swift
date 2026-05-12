import SwiftUI
import Payhub

/// The "More" tab: profile summary, entitlements, push toggle, password reset,
/// sign out, and an app/server footer.
struct MoreView: View {
    @EnvironmentObject private var repository: MerchantRepository
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var vm = MoreViewModel()

    @State private var showForgot = false
    @State private var showSignOutConfirm = false

    var body: some View {
        NavigationStack {
            List {
                profileSection
                if let me = repository.me, let ent = me.entitlements { entitlementsSection(ent) }
                notificationsSection
                securitySection
                businessSection
                reportsSection
                accountSection
                footerSection
            }
            .navigationTitle(LocalizedStringKey("more.title"))
            .refreshable { await vm.refresh() }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { vm.reloadMe() } label: { Image(systemName: "arrow.clockwise") }
                }
            }
            .navigationDestination(for: SettlementsRoute.self) { route in
                switch route {
                case let .file(id): SettlementDetailView(fileID: id)
                case let .payment(id): PaymentDetailView(paymentID: id)
                }
            }
            .navigationDestination(for: SubMerchantsRoute.self) { route in
                switch route {
                case let .detail(id): SubMerchantDetailView(subID: id)
                case let .users(sid): SubUsersView(subID: sid)
                }
            }
            .navigationDestination(for: MoreRoute.self) { route in
                switch route {
                case .settlements: SettlementsView()
                case .changePassword: ChangePasswordView()
                case .mfaSettings: MfaSettingsView()
                case .orgProfile: OrgProfileView()
                case .subMerchants: SubMerchantsView()
                }
            }
            .sheet(isPresented: $showForgot) {
                ForgotPasswordSheet(
                    initialMerchantCode: repository.me?.merchant.code ?? "",
                    initialUsername: repository.me?.username ?? "",
                    initialSubCode: repository.me?.subMerchant?.code ?? "")
            }
            .alert("Sign out?", isPresented: $showSignOutConfirm) {
                Button("Sign out", role: .destructive) { vm.signOut() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll need your merchant code, username, and password to sign back in.")
            }
            .alert(item: $vm.error) { err in
                Alert(title: Text(err.title), message: Text(err.message), dismissButton: .default(Text("OK")))
            }
        }
        .onAppear {
            vm.bind(repository: repository)
            Task { await vm.refresh() }
        }
    }

    // MARK: - Sections

    @ViewBuilder private var profileSection: some View {
        if let me = repository.me {
            Section {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(Brand.amberSoft)
                        Text(initials(me.fullName.isEmpty ? me.username : me.fullName))
                            .font(.headline).foregroundStyle(Brand.amberDeep)
                    }
                    .frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(me.fullName.isEmpty ? me.username : me.fullName)
                            .font(.headline)
                        Text("@\(me.username)").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)

                LabeledContent("Merchant", value: "\(me.merchant.name) (\(me.merchant.code))")
                if let sub = me.subMerchant {
                    LabeledContent("Shop", value: "\(sub.name) (\(sub.code))")
                }
                LabeledContent("Role") {
                    TagPill(text: roleLabel(me.role), color: Brand.roleColor(for: me.role))
                }
                if me.role != me.effectiveRole {
                    LabeledContent("Effective role") {
                        TagPill(text: roleLabel(me.effectiveRole), color: Brand.roleColor(for: me.effectiveRole))
                    }
                }
                if let email = me.email, !email.isEmpty { LabeledContent("Email", value: email) }
                if let mobile = me.mobile, !mobile.isEmpty { LabeledContent("Mobile", value: mobile) }
                LabeledContent("Two-factor") {
                    Text(me.mfaEnabled ? "On" : "Off").foregroundStyle(me.mfaEnabled ? .green : .secondary)
                }
            } header: {
                Text("Profile")
            } footer: {
                Text("Manage your two-factor and password here, or your full profile on the PayHub web portal.")
            }
        }
    }

    private var securitySection: some View {
        Section {
            NavigationLink(value: MoreRoute.changePassword) {
                Label(LocalizedStringKey("more.changePassword"), systemImage: "key")
            }
            NavigationLink(value: MoreRoute.mfaSettings) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LocalizedStringKey("more.twoFactor"))
                        Text(LocalizedStringKey((repository.me?.mfaEnabled ?? false) ? "more.twoFactorOn" : "more.twoFactorOff"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } icon: { Image(systemName: "lock.shield") }
            }
        } header: {
            Text(LocalizedStringKey("more.security"))
        }
    }

    @ViewBuilder private var businessSection: some View {
        if let me = repository.me, me.subMerchant == nil {
            Section {
                NavigationLink(value: MoreRoute.orgProfile) {
                    Label(LocalizedStringKey("more.orgProfile"), systemImage: "building.2")
                }
                if me.canManageSubs {
                    NavigationLink(value: MoreRoute.subMerchants) {
                        Label(LocalizedStringKey("more.subMerchants"), systemImage: "person.2.badge.gearshape")
                    }
                }
                // TODO(payhub): SUB_OWNER cashier self-management screen (subs managing their own staff)
            } header: {
                Text(LocalizedStringKey("more.business"))
            }
        }
    }

    private func entitlementsSection(_ ent: Entitlements) -> some View {
        Section("Plan") {
            LabeledContent("Aggregator (sub-merchants)") {
                Text(ent.aggregator ? "Enabled" : "Off").foregroundStyle(ent.aggregator ? .green : .secondary)
            }
            LabeledContent("Smart routing") {
                Text(ent.smartRouting ? "Enabled" : "Off").foregroundStyle(ent.smartRouting ? .green : .secondary)
            }
            LabeledContent("Active pay-link quota", value: ent.payLinkQuota > 0 ? "\(ent.payLinkQuota)" : "—")
        }
    }

    private var reportsSection: some View {
        Section {
            NavigationLink(value: MoreRoute.settlements) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LocalizedStringKey("more.settlements"))
                        Text(LocalizedStringKey("more.settlements.hint"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "doc.text.magnifyingglass")
                }
            }
        } header: {
            Text(LocalizedStringKey("more.reports"))
        }
    }

    private var notificationsSection: some View {
        Section {
            Toggle(isOn: Binding(get: { vm.pushEnabled }, set: { vm.setPush($0) })) {
                Label("Push notifications", systemImage: "bell.badge")
            }
        } header: {
            Text("Notifications")
        } footer: {
            if vm.pushAuthorizationDenied {
                Text("Notifications are turned off for PayHub Merchant in iOS Settings. Enable them there to receive pay-link reminders.")
            } else {
                Text("Get reminders when a pay-link is about to expire, and updates when one is paid.")
            }
        }
    }

    private var accountSection: some View {
        Section {
            Button {
                showForgot = true
            } label: { Label("Request password reset", systemImage: "key") }
            Button(role: .destructive) {
                showSignOutConfirm = true
            } label: {
                if vm.isSigningOut {
                    HStack { ProgressView(); Text("Signing out…") }
                } else {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
            .disabled(vm.isSigningOut)
        } header: {
            Text("Account")
        }
    }

    private var footerSection: some View {
        Section {
            LabeledContent("Version", value: AppInfo.versionDisplay)
            LabeledContent("Server", value: settings.serverURLString)
        } footer: {
            Text("PayHub is on-prem — the server URL was set when you signed in.")
        }
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let chars = parts.compactMap { $0.first }.map(String.init)
        return chars.joined().uppercased()
    }
}
