import SwiftUI

/// In-app "change password" — current / new / confirm, plus an authenticator-code
/// field when the account has two-factor on. Talks to `/merchant/auth/change-password`
/// (the bearer session survives — a 401 here is "wrong password", not a logout).
struct ChangePasswordView: View {
    @EnvironmentObject private var repository: MerchantRepository
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = ChangePasswordViewModel()

    var body: some View {
        Form {
            Section {
                SecureField(LocalizedStringKey("account.changepw.current"), text: $vm.oldPassword)
                    .textContentType(.password)
            }

            Section {
                SecureField(LocalizedStringKey("account.changepw.new"), text: $vm.newPassword)
                    .textContentType(.newPassword)
                SecureField(LocalizedStringKey("account.changepw.confirm"), text: $vm.confirmPassword)
                    .textContentType(.newPassword)
            } footer: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey("account.changepw.tooShort"))
                        .foregroundStyle(vm.passwordTooShort ? Color.red : Color.secondary)
                    if vm.passwordsMismatch {
                        Text(LocalizedStringKey("account.changepw.mismatch")).foregroundStyle(.red)
                    }
                }
            }

            if vm.showsCodeField {
                Section {
                    TextField(LocalizedStringKey("account.changepw.code"), text: $vm.code)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: vm.code) { newValue in
                            vm.code = String(newValue.filter(\.isNumber).prefix(8))
                        }
                } footer: {
                    Text(LocalizedStringKey("account.mfa.intro"))
                }
            }

            Section {
                Button {
                    vm.submit()
                } label: {
                    if vm.isSubmitting {
                        HStack { ProgressView(); Text(LocalizedStringKey("account.changepw.submit")) }
                    } else {
                        Text(LocalizedStringKey("account.changepw.submit"))
                    }
                }
                .disabled(!vm.canSubmit)
            }
        }
        .navigationTitle(LocalizedStringKey("account.changepw.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toast($vm.toast)
        .alert(item: $vm.error) { err in
            Alert(title: Text(err.title), message: Text(err.message), dismissButton: .default(Text(LocalizedStringKey("common.ok"))))
        }
        .onChange(of: vm.done) { if $0 { dismiss() } }
        .onAppear { vm.bind(repository: repository) }
        .interactiveDismissDisabled(vm.isSubmitting)
    }
}
