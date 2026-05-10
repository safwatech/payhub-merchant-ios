import Foundation
import Combine
import Payhub

@MainActor
final class PayLinkDetailViewModel: ObservableObject {
    let payLinkID: String

    @Published private(set) var link: PayLink?
    @Published private(set) var isLoading = false
    @Published private(set) var isMutating = false
    @Published var error: AppError?
    @Published var toast: Toast?
    /// Set when a clone is created → the view pushes its detail.
    @Published var clonedLinkID: String?

    private weak var repository: MerchantRepository?
    /// Called whenever `link` changes, so the list can splice the update in.
    var onUpdate: ((PayLink) -> Void)?

    init(payLinkID: String) { self.payLinkID = payLinkID }

    func bind(repository: MerchantRepository, onUpdate: ((PayLink) -> Void)?) {
        self.repository = repository
        self.onUpdate = onUpdate
    }

    var status: PayLinkStatus { PayLinkStatus(rawString: link?.status ?? "") }
    var canWrite: Bool { isWriteRole(repository?.me?.effectiveRole ?? "") }
    var isActive: Bool { status == .active }
    var canExtend: Bool { canWrite && isActive }
    var canCancel: Bool { canWrite && isActive }
    /// Clone is allowed regardless of status (you might clone an expired one).
    var canClone: Bool { canWrite }
    var canReshare: Bool { canWrite && link != nil }

    func load() async {
        guard let repository, link == nil else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            link = try await repository.payLink(payLinkID)
        } catch {
            self.error = AppError.from(error)
        }
    }

    func reload() async {
        guard let repository else { return }
        do { applyUpdated(try await repository.payLink(payLinkID)) }
        catch { self.error = AppError.from(error) }
    }

    // MARK: - Actions

    func extend(seconds: Int) {
        runMutation { repo in try await repo.extendPayLink(self.payLinkID, additionalSeconds: seconds) }
            onSuccess: { _ in self.toast = Toast(message: "Expiry extended", systemImage: "calendar.badge.plus") }
    }

    func cancel() {
        runMutation { repo in try await repo.cancelPayLink(self.payLinkID) }
            onSuccess: { _ in self.toast = Toast(message: "Pay-link cancelled", systemImage: "xmark.circle.fill") }
    }

    func markShared() {
        runMutation { repo in try await repo.markPayLinkShared(self.payLinkID) }
            onSuccess: { _ in self.toast = Toast(message: "Marked as shared", systemImage: "square.and.arrow.up") }
    }

    func clone() {
        guard let repository else { return }
        isMutating = true
        Task {
            defer { isMutating = false }
            do {
                let new = try await repository.clonePayLink(payLinkID)
                onUpdate?(new)   // surfaces the new link to the list too
                let id = new.id
                toast = Toast(message: "Cloned → \(new.merchantOrderRef)",
                              systemImage: "doc.on.doc.fill",
                              actionTitle: "Open",
                              action: { [weak self] in self?.clonedLinkID = id })
            } catch {
                self.error = AppError.from(error)
            }
        }
    }

    // MARK: - Plumbing

    private func runMutation(_ op: @escaping (MerchantRepository) async throws -> PayLink,
                             onSuccess: @escaping (PayLink) -> Void) {
        guard let repository else { return }
        isMutating = true
        Task {
            defer { isMutating = false }
            do {
                let updated = try await op(repository)
                applyUpdated(updated)
                onSuccess(updated)
            } catch {
                self.error = AppError.from(error)
            }
        }
    }

    private func applyUpdated(_ updated: PayLink) {
        link = updated
        onUpdate?(updated)
    }
}
