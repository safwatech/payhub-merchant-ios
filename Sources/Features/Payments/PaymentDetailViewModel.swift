import Foundation
import Combine
import Payhub

@MainActor
final class PaymentDetailViewModel: ObservableObject {
    @Published private(set) var payment: PaymentView?
    @Published private(set) var isLoading = false
    @Published var error: AppError?

    private weak var repository: MerchantRepository?
    private var paymentID: String = ""

    func bind(repository: MerchantRepository, paymentID: String) {
        self.repository = repository
        self.paymentID = paymentID
    }

    func load() async {
        guard let repository, !paymentID.isEmpty else { return }
        if payment == nil { isLoading = true }
        defer { isLoading = false }
        error = nil
        do {
            payment = try await repository.payment(paymentID)
        } catch {
            self.error = AppError.from(error)
        }
    }
}
