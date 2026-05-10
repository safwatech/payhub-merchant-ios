import SwiftUI

/// The sign-in screen. PayHub is on-prem, so the server URL is editable — tucked
/// into an "Advanced" disclosure with the sensible default pre-filled.
struct LoginView: View {
    @EnvironmentObject private var repository: MerchantRepository
    @EnvironmentObject private var router: AppRouter

    @StateObject private var vm = LoginViewModel()
    @State private var showForgot = false
    @State private var navigateToMFA = false
    @FocusState private var focused: Field?

    private enum Field { case merchant, sub, username, password, server }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    formCard
                    submitButton
                    Button("Forgot password?") { showForgot = true }
                        .font(.subheadline)
                    Text("PayHub Merchant \(AppInfo.versionDisplay)")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                }
                .padding(20)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .navigationDestination(isPresented: $navigateToMFA) {
                if let token = vm.mfaChallengeToken { MFAView(challengeToken: token) }
            }
            .sheet(isPresented: $showForgot) {
                ForgotPasswordSheet(initialMerchantCode: vm.merchantCode,
                                    initialUsername: vm.username,
                                    initialSubCode: vm.subCode)
            }
            .alert(item: $vm.error) { err in
                Alert(title: Text(err.title), message: Text(err.message), dismissButton: .default(Text("OK")))
            }
        }
        .onAppear {
            vm.bind(repository: repository)
            if case let .acceptInvite(_, m, u, s)? = router.pendingInvite {
                vm.prefill(merchantCode: m, username: u, subCode: s)
            }
        }
        .onChange(of: vm.mfaChallengeToken) { navigateToMFA = ($0 != nil) }
        .onChange(of: router.pendingInvite == nil) { wentNil in
            // Accept-invite sheet dismissed → pull any freshly-stashed identity bits.
            if wentNil { vm.refreshPrefillFromSettings() }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 14) {
            AppMarkView(size: 84)
            Text("PayHub Merchant")
                .font(.title.weight(.bold))
            Text("Sign in to your merchant or shop account")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 16)
    }

    private var submitButton: some View {
        Button {
            focused = nil
            vm.submit()
        } label: {
            if vm.isSubmitting {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                Text("Sign in").frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!vm.canSubmit)
    }

    private var formCard: some View {
        VStack(spacing: 0) {
            textRow(title: "Merchant code", systemImage: "building.2", text: $vm.merchantCode,
                    field: .merchant, content: .username, submit: .next)
            divider
            textRow(title: "Username", systemImage: "person", text: $vm.username,
                    field: .username, content: .username, submit: .next)
            divider
            secureRow(title: "Password", text: $vm.password, field: .password)

            DisclosureGroup(isExpanded: $vm.showAdvanced) {
                VStack(spacing: 0) {
                    textRow(title: "Shop code (optional)", systemImage: "storefront", text: $vm.subCode,
                            field: .sub, content: nil, submit: .next,
                            footnote: "Only for sub-merchant (shop) logins.")
                    divider
                    HStack {
                        Image(systemName: "server.rack").frame(width: 28).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Server URL").font(.caption).foregroundStyle(.secondary)
                            TextField("https://app.payhub.ly", text: $vm.serverURL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                                .focused($focused, equals: .server)
                        }
                        Button { vm.resetServerURL() } label: { Image(systemName: "arrow.counterclockwise") }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 10).padding(.horizontal, 12)
                }
            } label: {
                Label("Advanced", systemImage: "gearshape").font(.subheadline)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
        }
        .background(Brand.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var divider: some View { Divider().padding(.leading, 44) }

    @ViewBuilder
    private func textRow(title: String, systemImage: String, text: Binding<String>, field: Field,
                         content: UITextContentType?, submit: SubmitLabel, footnote: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: systemImage).frame(width: 28).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.caption).foregroundStyle(.secondary)
                    TextField(title, text: text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(content)
                        .submitLabel(submit)
                        .focused($focused, equals: field)
                        .onSubmit { advanceFocus(from: field) }
                }
            }
            if let footnote {
                Text(footnote).font(.caption2).foregroundStyle(.tertiary).padding(.leading, 28)
            }
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
    }

    @ViewBuilder
    private func secureRow(title: String, text: Binding<String>, field: Field) -> some View {
        HStack {
            Image(systemName: "lock").frame(width: 28).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                SecureField(title, text: text)
                    .textContentType(.password)
                    .submitLabel(.go)
                    .focused($focused, equals: field)
                    .onSubmit { vm.submit() }
            }
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
    }

    private func advanceFocus(from field: Field) {
        switch field {
        case .merchant: focused = .username
        case .username: focused = .password
        case .sub:      focused = .server
        default:        focused = nil
        }
    }
}
