import SwiftUI
import Payhub

/// Read-only settlement-files list. Lives under More → Settlements rather than
/// the bottom nav — reconciliation reports are checked far less often than
/// pay-links / payments. Tap a file → [SettlementDetailView].
struct SettlementsView: View {
    @EnvironmentObject private var repository: MerchantRepository
    @StateObject private var vm = SettlementsViewModel()

    var body: some View {
        content
            .navigationTitle(LocalizedStringKey("settlements.title"))
            .onAppear {
                vm.bind(repository: repository)
                vm.onAppear()
            }
    }

    @ViewBuilder private var content: some View {
        if vm.isLoading && vm.files.isEmpty {
            LoadingView(caption: NSLocalizedString("settlements.loading", value: "Loading…", comment: ""))
        } else if let error = vm.error, vm.files.isEmpty {
            ErrorStateView(error: error) { Task { await vm.refresh() } }
        } else if vm.files.isEmpty {
            EmptyStateView(
                title: NSLocalizedString("settlements.empty.title", value: "No settlement files yet", comment: ""),
                systemImage: "doc.text",
                description: NSLocalizedString(
                    "settlements.empty.body",
                    value: "When your PSP delivers a settlement file, it shows up here.",
                    comment: ""))
        } else {
            List {
                ForEach(vm.files) { file in
                    NavigationLink(value: SettlementsRoute.file(file.id)) {
                        SettlementRowView(file: file)
                    }
                    .task { await vm.loadMoreIfNeeded(currentItem: file) }
                }
                if vm.hasMore {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .refreshable { await vm.refresh() }
        }
    }
}

/// Routes pushed onto the Settlements navigation stack. Wrapped in an enum so
/// the same stack can also push a payment-detail (from a settlement row's
/// `payment_id`) without breaking the type-segregated `navigationDestination`.
enum SettlementsRoute: Hashable {
    case file(String)
    case payment(String)
}

private struct SettlementRowView: View {
    let file: Settlement

    var body: some View {
        // SDK 1.2 slimmed the settlement projection down to id / psp / period
        // / rowCount / totalMinor / currency / status. The matched/mismatch
        // counters live on the admin-side `/admin/settlements/{id}` view —
        // not on the merchant projection — so we surface what we have.
        VStack(alignment: .leading, spacing: 6) {
            Text(file.period)
                .font(.system(.subheadline, design: .monospaced).weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: 8) {
                Text(PSP.label(file.psp))
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.14), in: Capsule())
                if let date = ISO.date(from: file.createdAt) {
                    Text(String(format:
                        NSLocalizedString("settlements.uploadedAgo", value: "Uploaded %@", comment: "1$=relative time"),
                        RelativeTime.string(for: date)))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            HStack(spacing: 6) {
                Text(String(format:
                    NSLocalizedString("settlements.rowCount", value: "%d rows", comment: "1$=count"),
                    file.rowCount))
                    .font(.caption)
                Text(Money.format(minor: file.totalMinor, currency: file.currency))
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
