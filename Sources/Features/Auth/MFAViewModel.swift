import Foundation
import Combine

@MainActor
final class MFAViewModel: ObservableObject {
    let challengeToken: String

    @Published var code: String = ""
    @Published private(set) var isSubmitting = false
    @Published var error: AppError?

    private weak var repository: MerchantRepository?

    init(challengeToken: String) {
        self.challengeToken = challengeToken
    }

    func bind(repository: MerchantRepository) { self.repository = repository }

    var canSubmit: Bool {
        let digits = code.filter(\.isNumber)
        return digits.count >= 6 && digits.count <= 8 && !isSubmitting
    }

    func submit() {
        guard canSubmit, let repository else { return }
        error = nil
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            do {
                _ = try await repository.completeMFA(challengeToken: challengeToken, code: code.filter(\.isNumber))
                // authState flips → RootView swaps to MainTabView; this view is popped.
            } catch {
                self.error = AppError.from(error)
                code = ""
            }
        }
    }
}
