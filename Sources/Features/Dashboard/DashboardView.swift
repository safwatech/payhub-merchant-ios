import SwiftUI
import Payhub

/// The home screen: who you're signed in as, a window picker, four metric cards,
/// other payment outcomes, and (for parent merchants) a per-shop breakdown.
struct DashboardView: View {
    @EnvironmentObject private var repository: MerchantRepository
    @EnvironmentObject private var router: AppRouter
    @StateObject private var vm = DashboardViewModel()

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let me = repository.me { BrandHeader(me: me) }

                    windowPicker

                    if vm.isLoading && vm.dashboard == nil {
                        ProgressView().padding(.vertical, 40)
                    } else if let error = vm.error, vm.dashboard == nil {
                        ErrorStateView(error: error) { Task { await vm.refresh() } }
                            .frame(minHeight: 200)
                    } else {
                        metricCards
                        if !vm.otherOutcomes.isEmpty { otherOutcomesSection }
                        if let me = repository.me, me.subMerchant == nil { byShopSection }
                    }
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { Task { await vm.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(vm.isLoading)
                }
            }
            .refreshable { await vm.refresh() }
        }
        .onAppear {
            vm.bind(repository: repository)
            vm.onAppear()
        }
    }

    // MARK: - Sections

    private var windowPicker: some View {
        Picker("Window", selection: $vm.window) {
            ForEach(DashboardViewModel.Window.allCases) { w in Text(w.label).tag(w) }
        }
        .pickerStyle(.segmented)
    }

    private var metricCards: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            CounterCard(title: "Paid", value: "\(vm.paid.count)",
                        subtitle: Money.format(minor: vm.paid.volumeMinor, currency: vm.currency),
                        systemImage: "checkmark.circle.fill", tint: .green)
            CounterCard(title: "In flight", value: "\(vm.inflight)",
                        subtitle: "Awaiting completion", systemImage: "clock.fill", tint: .orange)
            CounterCard(title: "Active pay-links", value: "\(vm.activePayLinks)",
                        subtitle: "Tap to view", systemImage: "link", tint: .blue) {
                router.selectedTab = .payLinks
            }
            CounterCard(title: "Needs follow-up", value: "\(vm.needsFollowup)",
                        subtitle: "Expiring within 72h", systemImage: "bell.badge.fill", tint: .pink) {
                router.pendingPayLinkFilter = .needsFollowup
                router.selectedTab = .payLinks
            }
        }
    }

    private var otherOutcomesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Other outcomes")
                .font(.headline)
                .padding(.top, 4)
            VStack(spacing: 0) {
                ForEach(Array(vm.otherOutcomes.enumerated()), id: \.offset) { idx, outcome in
                    HStack {
                        Text(outcomeLabel(outcome.status))
                            .font(.subheadline)
                        Spacer()
                        Text("\(outcome.count)")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                        if outcome.volumeMinor > 0 {
                            Text(Money.format(minor: outcome.volumeMinor, currency: vm.currency))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    if idx < vm.otherOutcomes.count - 1 { Divider().padding(.leading, 14) }
                }
            }
            .background(Brand.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var byShopSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("By shop")
                .font(.headline)
                .padding(.top, 4)
            if vm.subRows.isEmpty {
                InfoBanner(text: "No per-shop activity for this window — or this server version doesn't break the dashboard down by shop yet. Open a shop's account to see its own dashboard.",
                           systemImage: "building.2")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(vm.subRows.enumerated()), id: \.element.id) { idx, row in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.name ?? row.code ?? row.subMerchantId)
                                    .font(.subheadline.weight(.medium))
                                if let code = row.code { Text(code).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(row.paid) paid · \(Money.format(minor: row.volumeMinor, currency: vm.currency))")
                                    .font(.caption).monospacedDigit()
                                Text("\(row.inflight) in flight · \(row.activePayLinks) links")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 10).padding(.horizontal, 14)
                        if idx < vm.subRows.count - 1 { Divider().padding(.leading, 14) }
                    }
                }
                .background(Brand.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private func outcomeLabel(_ status: String) -> String {
        switch status.lowercased() {
        case "succeeded": return "Succeeded"
        case "failed": return "Failed"
        case "pending", "processing": return "In progress"
        case "refunded": return "Refunded"
        case "cancelled", "canceled": return "Cancelled"
        case "expired": return "Expired"
        default: return status.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
