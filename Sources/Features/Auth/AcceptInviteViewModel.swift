import Foundation
import Combine

@MainActor
final class AcceptInviteViewModel: ObservableObject {
    let token: String
    let merchantCode: String?
    let username: String?
    let subCode: String?

    @Published var newPassword = ""
    @Published var confirmPassword = ""
    @Published private(set) var isSubmitting = false
    @Published var error: AppError?
    @Published private(set) var done = false

    private weak var repository: MerchantRepository?

    init(token: String, merchantCode: String?, username: String?, subCode: String?) {
        self.token = token
        self.merchantCode = merchantCode
        self.username = username
        self.subCode = subCode
    }

    convenience init(link: DeepLink) {
        if case let .acceptInvite(token, m, u, s) = link {
            self.init(token: token, merchantCode: m, username: u, subCode: s)
        } else {
            self.init(token: "", merchantCode: nil, username: nil, subCode: nil)
        }
    }

    func bind(repository: MerchantRepository) { self.repository = repository }

    /// Password policy hint mirrors the portal: ≥ 12 chars.
    var passwordTooShort: Bool { !newPassword.isEmpty && newPassword.count < 12 }
    var passwordsMismatch: Bool { !confirmPassword.isEmpty && newPassword != confirmPassword }

    var canSubmit: Bool {
        newPassword.count >= 12 && newPassword == confirmPassword && !isSubmitting && !token.isEmpty
    }

    func submit() {
        guard canSubmit, let repository else { return }
        error = nil
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            do {
                try await repository.acceptInvite(token: token, newPassword: newPassword)
                done = true
            } catch {
                self.error = AppError.from(error)
            }
        }
    }
}
