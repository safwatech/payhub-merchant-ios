import SwiftUI

/// Presented (as a sheet over login) when the app opens a
/// `payhub://accept-invite?token=…&m=…&u=…&s=…` link. Sets the new password,
/// then nudges the user back to the pre-filled login screen.
struct AcceptInviteView: View {
    @EnvironmentObject private var repository: MerchantRepository
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss

    @StateObject private var vm: AcceptInviteViewModel

    init(link: DeepLink) {
        _vm = StateObject(wrappedValue: AcceptInviteViewModel(link: link))
    }

    var body: some View {
        NavigationStack {
            Form {
                if vm.token.isEmpty {
                    Section {
                        Label("This invitation link is missing its token. Ask whoever invited you for a fresh link.",
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    }
                } else if vm.done {
                    Section {
                        Label("Your password is set. Sign in with the details below.",
                              systemImage: "checkmark.seal.fill")
                            .foregroundStyle(Brand.amber)
                    }
                    accountSummary
                } else {
                    Section("You're setting up access for") { accountSummaryRows }

                    Section {
                        SecureField("New password", text: $vm.newPassword)
                            .textContentType(.newPassword)
                        SecureField("Confirm password", text: $vm.confirmPassword)
                            .textContentType(.newPassword)
                    } footer: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Use at least 12 characters.")
                            if vm.passwordTooShort { Text("Too short.").foregroundStyle(.red) }
                            if vm.passwordsMismatch { Text("Passwords don't match.").foregroundStyle(.red) }
                        }
                    }

                    Section {
                        Button {
                            vm.submit()
                        } label: {
                            if vm.isSubmitting { ProgressView() } else { Text("Set password") }
                        }
                        .disabled(!vm.canSubmit)
                    }
                }
            }
            .navigationTitle("Accept invitation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(vm.done ? "Go to sign in" : "Cancel") { finish() }
                }
            }
            .alert(item: $vm.error) { err in
                Alert(title: Text(err.title), message: Text(err.message), dismissButton: .default(Text("OK")))
            }
        }
        .onAppear { vm.bind(repository: repository) }
        .onChange(of: vm.done) { if $0 { /* keep sheet; user taps "Go to sign in" */ } }
        .interactiveDismissDisabled(vm.isSubmitting)
    }

    @ViewBuilder private var accountSummary: some View {
        Section("Sign in with") { accountSummaryRows }
    }

    @ViewBuilder private var accountSummaryRows: some View {
        LabeledContent("Merchant code", value: vm.merchantCode ?? "—")
        LabeledContent("Username", value: vm.username ?? "—")
        if let s = vm.subCode, !s.isEmpty { LabeledContent("Shop code", value: s) }
    }

    private func finish() {
        // Stash the identity bits so the (already-constructed) login screen can
        // re-read them; the router's pending-invite link is cleared on dismiss.
        if let m = vm.merchantCode, !m.isEmpty { AppSettings.shared.lastMerchantCode = m }
        if let u = vm.username, !u.isEmpty { AppSettings.shared.lastUsername = u }
        if let s = vm.subCode, !s.isEmpty { AppSettings.shared.lastSubCode = s }
        dismiss()
    }
}
