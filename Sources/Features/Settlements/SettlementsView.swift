import SwiftUI

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
    let file: SettlementFile

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(file.filename)
                .font(.system(.subheadline, design: .monospaced).weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: 8) {
                Text(PSP.label(file.pspCode))
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
                    NSLocalizedString("settlements.matchedOfTotal", value: "%d/%d matched", comment: "1$=matched 2$=total"),
                    file.matchedCount, file.rowCount))
                    .font(.caption)
                if file.mismatchCount > 0 {
                    Text(String(format:
                        NSLocalizedString("settlements.mismatchCount", value: "%d mismatch", comment: "1$=count"),
                        file.mismatchCount))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .foregroundStyle(.red)
                        .background(Color.red.opacity(0.14), in: Capsule())
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
