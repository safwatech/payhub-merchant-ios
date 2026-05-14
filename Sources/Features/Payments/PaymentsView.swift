import SwiftUI
import Payhub

/// The payments tab: a filter menu + a `List` of payment rows + pull-to-refresh,
/// with a `NavigationLink` per row into [PaymentDetailView]. Read-only — the
/// mutating endpoints (force-resolve, refund, repoll) stay in the admin console.
struct PaymentsView: View {
    @EnvironmentObject private var repository: MerchantRepository
    @StateObject private var vm = PaymentsViewModel()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(LocalizedStringKey("payments.title"))
                .navigationDestination(for: String.self) { id in
                    PaymentDetailView(paymentID: id)
                }
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) { filterMenu }
                }
        }
        .onAppear {
            vm.bind(repository: repository)
            vm.onAppear()
        }
    }

    @ViewBuilder private var content: some View {
        if vm.isLoading && vm.payments.isEmpty {
            LoadingView(caption: NSLocalizedString("payments.loading", value: "Loading payments…", comment: ""))
        } else if let error = vm.error, vm.payments.isEmpty {
            ErrorStateView(error: error) { Task { await vm.refresh() } }
        } else if vm.payments.isEmpty {
            emptyState
        } else {
            list
        }
    }

    private var list: some View {
        List {
            ForEach(vm.payments) { row in
                NavigationLink(value: row.id) { PaymentRowView(row: row) }
                    .task { await vm.loadMoreIfNeeded(currentItem: row) }
            }
            if vm.hasMore {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .refreshable { await vm.refresh() }
    }

    private var emptyState: some View {
        let bodyText: String = vm.filter == .all
            ? NSLocalizedString("payments.empty.all", value: "Payments your customers make will show up here.", comment: "")
            : NSLocalizedString("payments.empty.filtered", value: "Nothing matches this filter right now.", comment: "")
        return EmptyStateView(
            title: NSLocalizedString("payments.empty.title", value: "No payments here", comment: ""),
            systemImage: vm.filter.systemImage,
            description: bodyText)
    }

    private var filterMenu: some View {
        Menu {
            Picker("Filter", selection: $vm.filter) {
                ForEach(PaymentStatusFilter.allCases) { f in
                    Label(f.label, systemImage: f.systemImage).tag(f)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: vm.filter.systemImage)
                Text(vm.filter.label)
                Image(systemName: "chevron.down").font(.caption2)
            }
            .font(.subheadline.weight(.medium))
        }
    }
}

/// One row in the payments list — amount + status pill + order ref + PSP + relative time.
struct PaymentRowView: View {
    let row: PaymentView
    private var status: PaymentStatus { PaymentStatus(rawString: row.status) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.merchantOrderRef)
                    .font(.system(.subheadline, design: .monospaced).weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Text(Money.format(minor: row.amountMinor, currency: row.currency))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
            HStack(spacing: 8) {
                paymentStatusBadge
                Text(PSP.label(row.psp ?? ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if let date = ISO.date(from: row.createdAt) {
                    Text(RelativeTime.string(for: date))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var paymentStatusBadge: some View {
        let color = status.tint
        return HStack(spacing: 4) {
            Image(systemName: status.systemImage).imageScale(.small)
            Text(status.label).font(.caption.weight(.semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.14), in: Capsule())
    }
}
