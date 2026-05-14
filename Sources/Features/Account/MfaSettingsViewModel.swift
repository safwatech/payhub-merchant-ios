import Foundation
import Combine
import Payhub

@MainActor
final class MfaSettingsViewModel: ObservableObject {
    /// Mirrors `repository.me?.mfaEnabled`, kept locally so a confirm/disable
    /// flips it instantly (the repo also `refreshMe()`s).
    @Published private(set) var mfaEnabled = false
    /// The enrolment payload while the user is mid-setup; `nil` otherwise.
    @Published private(set) var enrol: MfaEnrol?
    @Published var code = ""
    @Published var disablePassword = ""
    @Published private(set) var isWorking = false
    @Published var error: AppError?
    @Published var toast: Toast?

    private weak var repository: MerchantRepository?

    func bind(repository: MerchantRepository) {
        self.repository = repository
        mfaEnabled = repository.me?.mfaEnabled ?? false
    }

    var canConfirm: Bool {
        let digits = code.filter(\.isNumber)
        return digits.count >= 6 && digits.count <= 8 && !isWorking
    }
    var canDisable: Bool { !disablePassword.isEmpty && !isWorking }

    func startEnrol() {
        guard let repository, !isWorking else { return }
        error = nil
        isWorking = true
        Task {
            defer { isWorking = false }
            do { enrol = try await repository.mfaEnrol() }
            catch { self.error = AppError.from(error) }
        }
    }

    func cancelEnrol() { enrol = nil; code = "" }

    func confirm() {
        guard canConfirm, let repository else { return }
        error = nil
        isWorking = true
        let digits = code.filter(\.isNumber)
        Task {
            defer { isWorking = false }
            do {
                try await repository.mfaConfirm(code: digits)
                mfaEnabled = true
                enrol = nil
                code = ""
                toast = Toast(message: NSLocalizedString("account.mfa.enabledToast", value: "Two-factor enabled", comment: ""))
            } catch {
                self.error = AppError.from(error)
                code = ""
            }
        }
    }

    func disable() {
        guard canDisable, let repository else { return }
        error = nil
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await repository.mfaDisable(password: disablePassword)
                mfaEnabled = false
                disablePassword = ""
                toast = Toast(message: NSLocalizedString("account.mfa.disabledToast", value: "Two-factor disabled", comment: ""))
            } catch {
                self.error = AppError.from(error)
                disablePassword = ""
            }
        }
    }
}
