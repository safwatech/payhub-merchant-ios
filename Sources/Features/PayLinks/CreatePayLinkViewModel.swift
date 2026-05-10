import Foundation
import Combine
import Payhub

@MainActor
final class CreatePayLinkViewModel: ObservableObject {
    @Published var amountText: String = ""
    @Published var description: String = ""
    @Published var customerPhone: String = ""
    @Published var selectedPSPs: Set<String> = []     // empty = "all"
    @Published var expiryDays: Int = 7
    @Published var merchantOrderRef: String = ""

    @Published private(set) var isSubmitting = false
    @Published var error: AppError?
    /// The created link — drives the confirmation screen.
    @Published private(set) var created: PayLink?

    let currency = "LYD"
    private weak var repository: MerchantRepository?

    /// Max TTL the portal allows (mirror of `pay_link_max_ttl`, ~30 days). Used
    /// to clamp the stepper; the server is still the source of truth.
    let maxExpiryDays = 30

    func bind(repository: MerchantRepository) {
        self.repository = repository
        if merchantOrderRef.isEmpty { merchantOrderRef = generateOrderRef() }
    }

    var amountMinor: Int64? { Money.toMinor(majorString: amountText, currency: currency) }

    var canSubmit: Bool {
        guard let minor = amountMinor, minor > 0 else { return false }
        return !merchantOrderRef.trimmed.isEmpty && expiryDays >= 1 && !isSubmitting
    }

    func submit() {
        guard canSubmit, let repository, let minor = amountMinor else { return }
        error = nil
        isSubmitting = true
        let request = CreatePayLinkRequest(
            amountMinor: minor,
            merchantOrderRef: merchantOrderRef.trimmed,
            currency: currency,
            description: description.trimmed.isEmpty ? nil : description.trimmed,
            allowedPSPs: selectedPSPs.isEmpty ? nil : Array(selectedPSPs).sorted(),
            customerMSISDNHint: customerPhone.trimmed.isEmpty ? nil : customerPhone.trimmed,
            expiresInSeconds: expiryDays * 86_400,
            language: "both")
        Task {
            defer { isSubmitting = false }
            do {
                created = try await repository.createPayLink(request)
            } catch {
                self.error = AppError.from(error)
            }
        }
    }

    /// After the confirmation screen's `ShareLink`, mark the link shared so the
    /// portal's reshare signal is accurate.
    func markSharedAfterCreate() {
        guard let id = created?.id, let repository else { return }
        Task { _ = try? await repository.markPayLinkShared(id) }
    }

    func regenerateOrderRef() { merchantOrderRef = generateOrderRef() }

    private func generateOrderRef() -> String {
        let slug = merchantSlug()
        let digits = String(format: "%07d", Int.random(in: 0...9_999_999))
        return "\(slug)-\(digits)"
    }

    private func merchantSlug() -> String {
        let code = repository?.me?.merchant.code ?? "order"
        let lowered = code.lowercased()
        let allowed = lowered.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "-" }
        let slug = String(String.UnicodeScalarView(allowed))
        return slug.isEmpty ? "order" : String(slug.prefix(16))
    }
}
