import Foundation
import Combine
import Payhub

@MainActor
final class PayLinksViewModel: ObservableObject {
    @Published var filter: PayLinkFilter = .all {
        didSet { if oldValue != filter { Task { await load(reset: true) } } }
    }
    @Published private(set) var links: [PayLink] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published var error: AppError?

    private weak var repository: MerchantRepository?
    private var cursor: String?
    private var didInitialLoad = false

    func bind(repository: MerchantRepository) { self.repository = repository }

    func onAppear() {
        guard !didInitialLoad else { return }
        didInitialLoad = true
        Task { await load(reset: true) }
    }

    func refresh() async { await load(reset: true) }

    var hasMore: Bool { cursor != nil }

    func load(reset: Bool) async {
        guard let repository else { return }
        if reset {
            isLoading = true
            cursor = nil
        } else {
            guard cursor != nil, !isLoadingMore else { return }
            isLoadingMore = true
        }
        error = nil
        defer { isLoading = false; isLoadingMore = false }
        do {
            let page = try await repository.payLinks(filter: filter, cursor: reset ? nil : cursor)
            if reset { links = page.items } else { links.append(contentsOf: page.items) }
            cursor = page.nextCursor
        } catch {
            self.error = AppError.from(error)
        }
    }

    func loadMoreIfNeeded(currentItem: PayLink) async {
        guard let last = links.last, last.id == currentItem.id, hasMore else { return }
        await load(reset: false)
    }

    /// Splice an updated link back into the list (after cancel/extend/clone/share).
    func apply(_ updated: PayLink) {
        if let i = links.firstIndex(where: { $0.id == updated.id }) {
            // If the new status falls outside the current filter, drop it.
            if matchesFilter(updated) { links[i] = updated } else { links.remove(at: i) }
        } else if matchesFilter(updated), filter == .all {
            links.insert(updated, at: 0)
        }
    }

    func remove(id: String) {
        links.removeAll { $0.id == id }
    }

    private func matchesFilter(_ link: PayLink) -> Bool {
        let status = PayLinkStatus(rawString: link.status)
        switch filter {
        case .all: return true
        case .active: return status == .active
        case .paid: return status == .paid
        case .expired: return status == .expired
        case .cancelled: return status == .cancelled
        case .needsFollowup:
            return status == .active && RelativeTime.isWithin(hours: 72, of: link.expiresAt)
        }
    }
}
