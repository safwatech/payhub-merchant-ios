import Foundation
import Combine
import Payhub

/// Filter chips on the settlement-detail rows view.
enum SettlementRowFilter: String, CaseIterable, Identifiable {
    case all
    case matched
    case mismatch
    case missingInHub = "missing_in_hub"
    case missingInPsp = "missing_in_psp"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return NSLocalizedString("settlements.row.filter.all", value: "All", comment: "")
        case .matched: return NSLocalizedString("settlements.row.filter.matched", value: "Matched", comment: "")
        case .mismatch: return NSLocalizedString("settlements.row.filter.mismatch", value: "Mismatch", comment: "")
        case .missingInHub: return NSLocalizedString("settlements.row.filter.missingInHub", value: "Missing in hub", comment: "")
        case .missingInPsp: return NSLocalizedString("settlements.row.filter.missingInPsp", value: "Missing in PSP", comment: "")
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "tray.full"
        case .matched: return "checkmark.seal"
        case .mismatch: return "exclamationmark.triangle"
        case .missingInHub: return "questionmark.app.dashed"
        case .missingInPsp: return "questionmark.app"
        }
    }

    var wire: String? { self == .all ? nil : rawValue }
}

@MainActor
final class SettlementDetailViewModel: ObservableObject {
    /// Active row-status filter — applied **client-side** in 0.4.0 because
    /// the SDK 1.2 settlements-rows endpoint doesn't carry a server-side
    /// status query (cursor + limit only). The unfiltered `rawRows` is the
    /// authoritative copy; `rows` is the published derived view.
    @Published var filter: SettlementRowFilter = .all {
        didSet { if oldValue != filter { reapplyFilter() } }
    }
    @Published private(set) var file: Settlement?
    @Published private(set) var rows: [SettlementRow] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = false
    @Published var error: AppError?

    private weak var repository: MerchantRepository?
    private var fileID: String = ""
    private var didInitialLoad = false
    private static let pageSize = 100
    private var nextCursor: String?
    /// Full unfiltered row list — `rows` is `rawRows.filter(filter.wire)`.
    private var rawRows: [SettlementRow] = []

    func bind(repository: MerchantRepository, fileID: String) {
        self.repository = repository
        self.fileID = fileID
    }

    func onAppear() {
        guard !didInitialLoad else { return }
        didInitialLoad = true
        Task {
            await loadFile()
            await loadRows(reset: true)
        }
    }

    func refresh() async {
        await loadFile()
        await loadRows(reset: true)
    }

    func loadMoreIfNeeded(currentItem: SettlementRow) async {
        guard let last = rows.last, last.id == currentItem.id, hasMore else { return }
        await loadRows(reset: false)
    }

    private func loadFile() async {
        guard let repository, !fileID.isEmpty else { return }
        do {
            file = try await repository.settlement(fileID)
        } catch {
            // Non-fatal: the row list can still render without the header.
            self.error = AppError.from(error)
        }
    }

    private func loadRows(reset: Bool) async {
        guard let repository, !fileID.isEmpty else { return }
        if reset {
            isLoading = true
            nextCursor = nil
            rawRows.removeAll(keepingCapacity: true)
        } else {
            guard hasMore, !isLoadingMore else { return }
            isLoadingMore = true
        }
        error = nil
        defer { isLoading = false; isLoadingMore = false }
        do {
            let page = try await repository.settlementRows(
                fileID: fileID, after: nextCursor, limit: Self.pageSize)
            rawRows.append(contentsOf: page.items)
            nextCursor = page.cursor
            hasMore = page.cursor != nil && !page.items.isEmpty
            reapplyFilter()
        } catch {
            self.error = AppError.from(error)
        }
    }

    /// Apply the client-side filter chip to `rawRows`. Cheap — settlements
    /// are small batches (page size = 100, file row counts are bounded by
    /// the daily PSP reconcile run).
    private func reapplyFilter() {
        if let wire = filter.wire {
            rows = rawRows.filter { $0.status == wire }
        } else {
            rows = rawRows
        }
    }
}
