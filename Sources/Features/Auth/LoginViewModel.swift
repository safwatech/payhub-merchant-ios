import Foundation
import Combine
import Payhub

@MainActor
final class LoginViewModel: ObservableObject {
    @Published var serverURL: String
    @Published var merchantCode: String
    @Published var subCode: String
    @Published var username: String
    @Published var password: String = ""
    @Published var showAdvanced: Bool

    @Published private(set) var isSubmitting = false
    @Published var error: AppError?
    /// Non-nil when the server demands a second factor — drives navigation to `MFAView`.
    @Published var mfaChallengeToken: String?

    /// Wired by the view in `.onAppear` (environment objects aren't available at init).
    private weak var repository: MerchantRepository?
    private let settings: AppSettings

    init(settings: AppSettings = .shared) {
        self.settings = settings
        self.serverURL = settings.serverURLString
        self.merchantCode = settings.lastMerchantCode ?? ""
        self.username = settings.lastUsername ?? ""
        self.subCode = settings.lastSubCode ?? ""
        self.showAdvanced = settings.serverURLString != PayhubClient.defaultBaseURL.absoluteString
    }

    func bind(repository: MerchantRepository) {
        self.repository = repository
    }

    /// Pre-fill from an accept-invite deep-link redirect.
    func prefill(merchantCode: String?, username: String?, subCode: String?) {
        if let m = merchantCode, !m.isEmpty { self.merchantCode = m }
        if let u = username, !u.isEmpty { self.username = u }
        if let s = subCode, !s.isEmpty { self.subCode = s; self.showAdvanced = true }
    }

    /// Re-read the remembered-identity fields (after an accept-invite flow that
    /// stashed fresh values into `AppSettings`).
    func refreshPrefillFromSettings() {
        if let m = settings.lastMerchantCode, !m.isEmpty, merchantCode.isEmpty { merchantCode = m }
        if let u = settings.lastUsername, !u.isEmpty, username.isEmpty { username = u }
        if let s = settings.lastSubCode, !s.isEmpty, subCode.isEmpty { subCode = s; showAdvanced = true }
    }

    var canSubmit: Bool {
        !merchantCode.trimmed.isEmpty && !username.trimmed.isEmpty && !password.isEmpty
            && !serverURL.trimmed.isEmpty && !isSubmitting
    }

    func resetServerURL() { serverURL = PayhubClient.defaultBaseURL.absoluteString }

    func submit() {
        guard canSubmit, let repository else { return }
        error = nil
        isSubmitting = true
        repository.updateServerURL(serverURL.trimmed)
        Task {
            defer { isSubmitting = false }
            do {
                let outcome = try await repository.login(
                    merchantCode: merchantCode.trimmed, username: username.trimmed,
                    password: password, subCode: subCode.trimmed.isEmpty ? nil : subCode.trimmed)
                settings.lastMerchantCode = merchantCode.trimmed
                settings.lastUsername = username.trimmed
                settings.lastSubCode = subCode.trimmed.isEmpty ? nil : subCode.trimmed
                switch outcome {
                case .authenticated:
                    password = ""    // RootView swaps to MainTabView via authState
                case let .mfaRequired(challengeToken):
                    mfaChallengeToken = challengeToken
                }
            } catch {
                self.error = AppError.from(error)
            }
        }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
