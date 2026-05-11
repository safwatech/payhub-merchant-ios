import SwiftUI

/// Settlement-file detail: header card with the per-file counters, filter
/// chips, and a paginated list of reconciliation rows. Rows with a
/// `payment_id` deep-link into the matching payment detail.
struct SettlementDetailView: View {
    let fileID: String
    @EnvironmentObject private var repository: MerchantRepository
    @StateObject private var vm = SettlementDetailViewModel()

    var body: some View {
        List {
            if let file = vm.file {
                Section { HeaderCard(file: file) }
            }
            Section {
                filterChips
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            rowsSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(LocalizedStringKey("settlements.detail.title"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await vm.refresh() }
        .onAppear {
            vm.bind(repository: repository, fileID: fileID)
            vm.onAppear()
        }
    }

    @ViewBuilder private var rowsSection: some View {
        if vm.isLoading && vm.rows.isEmpty {
            Section { HStack { Spacer(); ProgressView(); Spacer() } }
        } else if let error = vm.error, vm.rows.isEmpty, vm.file == nil {
            Section { ErrorStateView(error: error) { Task { await vm.refresh() } } }
        } else if vm.rows.isEmpty {
            Section {
                Text(LocalizedStringKey("settlements.detail.noRows"))
                    .foregroundStyle(.secondary)
            }
        } else {
            Section(LocalizedStringKey("settlements.detail.rows")) {
                ForEach(vm.rows) { row in
                    if let paymentID = row.paymentId, !paymentID.isEmpty {
                        NavigationLink(value: SettlementsRoute.payment(paymentID)) {
                            SettlementRowItem(row: row)
                        }
                        .task { await vm.loadMoreIfNeeded(currentItem: row) }
                    } else {
                        SettlementRowItem(row: row)
                            .task { await vm.loadMoreIfNeeded(currentItem: row) }
                    }
                }
                if vm.hasMore {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
            }
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SettlementRowFilter.allCases) { f in
                    let selected = vm.filter == f
                    Button {
                        vm.filter = f
                    } label: {
                        Label(f.label, systemImage: f.systemImage)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .background(selected ? Color.accentColor : Color.secondary.opacity(0.14),
                                        in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct HeaderCard: View {
    let file: SettlementFile

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(file.filename)
                .font(.system(.subheadline, design: .monospaced).weight(.medium))
                .lineLimit(2)
            HStack(spacing: 8) {
                Text(PSP.label(file.pspCode))
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.14), in: Capsule())
                if let date = ISO.date(from: file.createdAt) {
                    Text(String(format:
                        NSLocalizedString("settlements.uploadedAgo", value: "Uploaded %@", comment: ""),
                        RelativeTime.string(for: date)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if let from = file.periodFrom ?? file.periodTo {
                Text(String(format:
                    NSLocalizedString("settlements.detail.period", value: "Period: %@ → %@", comment: ""),
                    file.periodFrom ?? "—",
                    file.periodTo ?? from))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider().padding(.vertical, 2)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    counter(NSLocalizedString("settlements.counter.total", value: "Total", comment: ""), file.rowCount)
                    counter(NSLocalizedString("settlements.counter.matched", value: "Matched", comment: ""), file.matchedCount)
                    counter(NSLocalizedString("settlements.counter.mismatch", value: "Mismatch", comment: ""),
                            file.mismatchCount, prominent: file.mismatchCount > 0)
                    counter(NSLocalizedString("settlements.counter.missingInHub", value: "Missing — hub", comment: ""),
                            file.missingInHubCount, prominent: file.missingInHubCount > 0)
                    counter(NSLocalizedString("settlements.counter.missingInPsp", value: "Missing — PSP", comment: ""),
                            file.missingInPspCount, prominent: file.missingInPspCount > 0)
                }
            }
        }
    }

    private func counter(_ label: String, _ value: Int, prominent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(prominent ? Color.red : Color.primary)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private struct SettlementRowItem: View {
    let row: SettlementRow
    private static let maxDiffFields = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                statusBadge
                Text(row.merchantOrderRef ?? row.pspRef ?? "—")
                    .font(.system(.subheadline, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                if let amount = row.amountMinor, let cur = row.currency {
                    Text(Money.format(minor: amount, currency: cur))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
            }
            HStack(spacing: 8) {
                if let psp = row.pspStatus, !psp.isEmpty {
                    Text(String(format:
                        NSLocalizedString("settlements.row.pspStatus", value: "PSP: %@", comment: ""), psp))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let psp = row.pspRef, !psp.isEmpty, row.merchantOrderRef != nil {
                    Text(psp)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            if !row.diff.isEmpty { diffView }
        }
        .padding(.vertical, 2)
    }

    private var statusBadge: some View {
        let color: Color
        switch row.status {
        case "matched": color = .green
        case "mismatch": color = .red
        case "missing_in_hub", "missing_in_psp": color = .orange
        default: color = .secondary
        }
        return Text(row.status.replacingOccurrences(of: "_", with: " "))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: Capsule())
    }

    private var diffView: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(row.diff.keys.sorted().prefix(Self.maxDiffFields)), id: \.self) { key in
                let payload = row.diff[key]
                let hub = payload?.string(forKey: "hub") ?? "—"
                let psp = payload?.string(forKey: "psp") ?? "—"
                Text(String(format:
                    NSLocalizedString("settlements.diffRow", value: "%@ — hub: %@ · psp: %@", comment: ""),
                    key, hub, psp))
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
            if row.diff.count > Self.maxDiffFields {
                Text(String(format:
                    NSLocalizedString("settlements.diffMore", value: "+%d more", comment: ""),
                    row.diff.count - Self.maxDiffFields))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 2)
    }
}
