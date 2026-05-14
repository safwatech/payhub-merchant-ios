import Foundation
import Combine

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
    @Published var filter: SettlementRowFilter = .all {
        didSet { if oldValue != filter { Task { await loadRows(reset: true) } } }
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
        } else {
            guard hasMore, !isLoadingMore else { return }
            isLoadingMore = true
        }
        error = nil
        defer { isLoading = false; isLoadingMore = false }
        do {
            let offset = reset ? 0 : rows.count
            let page = try await repository.settlementRows(
                fileID: fileID, statusFilter: filter.wire,
                limit: Self.pageSize, offset: offset)
            if reset { rows = page } else { rows.append(contentsOf: page) }
            hasMore = page.count >= Self.pageSize
        } catch {
            self.error = AppError.from(error)
        }
    }
}
