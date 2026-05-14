import Foundation
import Combine
import Payhub

@MainActor
final class ChangePasswordViewModel: ObservableObject {
    @Published var oldPassword = ""
    @Published var newPassword = ""
    @Published var confirmPassword = ""
    @Published var code = ""
    /// Once the server says `mfa_required` (e.g. `me` was stale), keep the code
    /// field visible until success.
    @Published private(set) var mfaRevealedByServer = false
    @Published private(set) var isSubmitting = false
    @Published private(set) var done = false
    @Published var error: AppError?
    @Published var toast: Toast?

    private weak var repository: MerchantRepository?

    func bind(repository: MerchantRepository) { self.repository = repository }

    /// Show the authenticator-code field when the account has MFA on, or once the
    /// server has asked for it.
    var showsCodeField: Bool { (repository?.me?.mfaEnabled ?? false) || mfaRevealedByServer }

    var passwordTooShort: Bool { !newPassword.isEmpty && newPassword.count < 12 }
    var passwordsMismatch: Bool { !confirmPassword.isEmpty && newPassword != confirmPassword }

    var canSubmit: Bool {
        !oldPassword.isEmpty
            && newPassword.count >= 12
            && newPassword == confirmPassword
            && !isSubmitting
    }

    func submit() {
        guard canSubmit, let repository else { return }
        error = nil
        isSubmitting = true
        let codeDigits = code.filter(\.isNumber)
        Task {
            defer { isSubmitting = false }
            do {
                try await repository.changePassword(
                    oldPassword: oldPassword,
                    newPassword: newPassword,
                    code: showsCodeField && !codeDigits.isEmpty ? codeDigits : nil)
                done = true
                toast = Toast(message: NSLocalizedString("account.changepw.success", value: "Password changed", comment: ""))
            } catch {
                let app = AppError.from(error)
                if app.requiresMFACode { mfaRevealedByServer = true }
                self.error = app
                code = ""
            }
        }
    }
}
