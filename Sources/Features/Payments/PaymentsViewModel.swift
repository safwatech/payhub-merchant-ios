import Foundation
import Combine
import Payhub

@MainActor
final class PaymentsViewModel: ObservableObject {
    @Published var filter: PaymentStatusFilter = .all {
        didSet { if oldValue != filter { Task { await load(reset: true) } } }
    }
    @Published private(set) var payments: [PaymentView] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = false
    @Published var error: AppError?

    private weak var repository: MerchantRepository?
    private var didInitialLoad = false
    private static let pageSize = 50
    /// Opaque cursor from the previous page; `nil` ⇒ start from the top.
    private var nextCursor: String?

    func bind(repository: MerchantRepository) { self.repository = repository }

    func onAppear() {
        guard !didInitialLoad else { return }
        didInitialLoad = true
        Task { await load(reset: true) }
    }

    func refresh() async { await load(reset: true) }

    func loadMoreIfNeeded(currentItem: PaymentView) async {
        guard let last = payments.last, last.id == currentItem.id, hasMore else { return }
        await load(reset: false)
    }

    private func load(reset: Bool) async {
        guard let repository else { return }
        if reset {
            isLoading = true
            nextCursor = nil
        } else {
            guard hasMore, !isLoadingMore else { return }
            isLoadingMore = true
        }
        error = nil
        defer { isLoading = false; isLoadingMore = false }
        do {
            let page = try await repository.payments(
                status: filter.wire, after: nextCursor, limit: Self.pageSize)
            if reset { payments = page.items } else { payments.append(contentsOf: page.items) }
            nextCursor = page.cursor
            // Cursor-based paging: a nil cursor means we've hit the end.
            hasMore = page.cursor != nil && !page.items.isEmpty
        } catch {
            self.error = AppError.from(error)
        }
    }
}
