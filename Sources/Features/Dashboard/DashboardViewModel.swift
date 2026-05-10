import Foundation
import Combine
import Payhub

@MainActor
final class DashboardViewModel: ObservableObject {
    /// Windows the API supports (caps at 168h).
    enum Window: Int, CaseIterable, Identifiable {
        case day = 24, threeDays = 72, week = 168
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .day: return "24h"
            case .threeDays: return "3d"
            case .week: return "7d"
            }
        }
    }

    @Published var window: Window = .day {
        didSet { if oldValue != window { Task { await load() } } }
    }
    @Published private(set) var dashboard: MerchantDashboard?
    @Published private(set) var subRows: [SubBreakdownRow] = []
    @Published private(set) var isLoading = false
    @Published private(set) var subBreakdownUnavailable = false
    @Published var error: AppError?

    private weak var repository: MerchantRepository?
    private var didInitialLoad = false

    func bind(repository: MerchantRepository) { self.repository = repository }

    /// `me` from the repo — used to decide whether to fetch the per-shop breakdown
    /// (parent users only).
    private var isParent: Bool { repository?.me?.subMerchant == nil }

    func onAppear() {
        guard !didInitialLoad else { return }
        didInitialLoad = true
        Task { await load() }
    }

    func refresh() async { await load() }

    private func load() async {
        guard let repository else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            async let main = repository.dashboard(windowHours: window.rawValue)
            if isParent {
                // Best-effort: the SDK can't decode the breakdown, so we do a raw GET.
                do {
                    let rows = try await repository.dashboardBySub(windowHours: window.rawValue)
                    subRows = rows
                    subBreakdownUnavailable = false
                } catch {
                    subRows = []
                    subBreakdownUnavailable = true   // server may not include `sub_breakdown` — fine
                }
            } else {
                subRows = []
            }
            dashboard = try await main
        } catch {
            self.error = AppError.from(error)
        }
    }

    // MARK: - Derived display

    /// Count + volume of succeeded payments in the window.
    var paid: (count: Int, volumeMinor: Int64) {
        let succeeded = dashboard?.paymentsByStatus.first { $0.status.lowercased() == "succeeded" }
        return (succeeded?.count ?? 0, succeeded?.volumeMinor ?? 0)
    }

    var inflight: Int { dashboard?.inflight ?? 0 }
    var activePayLinks: Int { dashboard?.activePayLinks ?? 0 }
    var needsFollowup: Int { dashboard?.needsFollowup ?? 0 }

    /// Currency for the volume line — the dashboard endpoint doesn't echo a
    /// currency, so we assume the install's primary currency (LYD for Libya).
    var currency: String { "LYD" }

    /// Non-succeeded, non-zero rows for the "Other outcomes" list.
    var otherOutcomes: [DashboardOutcome] {
        (dashboard?.paymentsByStatus ?? []).filter { $0.status.lowercased() != "succeeded" && $0.count > 0 }
    }
}
