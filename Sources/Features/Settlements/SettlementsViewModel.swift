import Foundation
import Combine
import Payhub

@MainActor
final class SettlementsViewModel: ObservableObject {
    @Published private(set) var files: [Settlement] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = false
    @Published var error: AppError?

    private weak var repository: MerchantRepository?
    private var didInitialLoad = false
    private static let pageSize = 50
    private var nextCursor: String?

    func bind(repository: MerchantRepository) { self.repository = repository }

    func onAppear() {
        guard !didInitialLoad else { return }
        didInitialLoad = true
        Task { await load(reset: true) }
    }

    func refresh() async { await load(reset: true) }

    func loadMoreIfNeeded(currentItem: Settlement) async {
        guard let last = files.last, last.id == currentItem.id, hasMore else { return }
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
            let page = try await repository.settlements(after: nextCursor, limit: Self.pageSize)
            if reset { files = page.items } else { files.append(contentsOf: page.items) }
            nextCursor = page.cursor
            hasMore = page.cursor != nil && !page.items.isEmpty
        } catch {
            self.error = AppError.from(error)
        }
    }
}
