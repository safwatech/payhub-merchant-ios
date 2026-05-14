import SwiftUI
import Payhub

/// Read-only payment detail: amount + status pill, summary card, full event
/// timeline (rendered as a SF-symbol-led list), remaining metadata, and a
/// "View pay-link" button when the payment was minted by one.
struct PaymentDetailView: View {
    let paymentID: String
    @EnvironmentObject private var repository: MerchantRepository
    @EnvironmentObject private var router: AppRouter
    @StateObject private var vm = PaymentDetailViewModel()

    @State private var toast: Toast?

    var body: some View {
        Group {
            if vm.isLoading && vm.payment == nil {
                LoadingView(caption: NSLocalizedString("common.loading", value: "Loading…", comment: ""))
            } else if let error = vm.error, vm.payment == nil {
                ErrorStateView(error: error) { Task { await vm.load() } }
            } else if let p = vm.payment {
                content(for: p)
            } else {
                Color.clear
            }
        }
        .navigationTitle(LocalizedStringKey("payment.detail.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toast($toast)
        .task {
            vm.bind(repository: repository, paymentID: paymentID)
            await vm.load()
        }
        .refreshable { await vm.load() }
    }

    @ViewBuilder private func content(for p: PaymentView) -> some View {
        let status = PaymentStatus(rawString: p.status)
        // SDK 1.2 dropped the `metadata` bag from `PaymentView` — the server
        // still has it server-side, but the merchant-portal projection is now
        // the slim shape (`description` + `customerMsisdnHint` + typed
        // fields). 0.4.0 surfaces what the SDK exposes; restoring the
        // bag-as-table view is queued for a follow-up that lands a
        // `payments.get(includeMetadata: true)` overload on the SDK.
        let customerMobile: String? = p.customerMsisdnHint
        let payLinkID: String? = nil
        let extras: [String: String] = [:]

        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: status.systemImage)
                            .font(.title2)
                            .foregroundStyle(status.tint)
                        Text(status.label)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(status.tint)
                        Spacer()
                    }
                    Text(Money.format(minor: p.amountMinor, currency: p.currency))
                        .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                }
                .padding(.vertical, 6)
            }

            Section {
                LabeledContent(LocalizedStringKey("payment.detail.orderRef")) {
                    HStack {
                        Text(p.merchantOrderRef)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button {
                            UIPasteboard.general.string = p.merchantOrderRef
                            toast = Toast(message: NSLocalizedString("common.copied", value: "Copied", comment: ""))
                        } label: { Image(systemName: "doc.on.doc") }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(NSLocalizedString("common.copy", value: "Copy", comment: ""))
                    }
                }
                LabeledContent(LocalizedStringKey("payment.detail.psp"), value: PSP.label(p.psp ?? ""))
                if let pspRef = p.pspRef, !pspRef.isEmpty {
                    LabeledContent(LocalizedStringKey("payment.detail.pspRef")) {
                        Text(pspRef).font(.system(.body, design: .monospaced))
                    }
                }
                if let mobile = customerMobile {
                    LabeledContent(LocalizedStringKey("payment.detail.customerMobile"), value: mobile)
                }
                if let created = ISO.date(from: p.createdAt) {
                    LabeledContent(LocalizedStringKey("payment.detail.created"),
                                   value: created.formatted(date: .abbreviated, time: .shortened))
                }
                if let updatedAt = p.updatedAt, updatedAt != p.createdAt,
                   let updated = ISO.date(from: updatedAt) {
                    LabeledContent(LocalizedStringKey("payment.detail.lastUpdate"),
                                   value: updated.formatted(date: .abbreviated, time: .shortened))
                }
            }

            if let payLinkID {
                Section {
                    Button {
                        // Routing through the AppRouter pops over to the pay-links
                        // tab + pushes detail — same as a push deep link.
                        router.handle(.payLink(id: payLinkID))
                    } label: {
                        Label(LocalizedStringKey("payment.detail.viewPayLink"), systemImage: "link")
                    }
                }
            }

            Section(LocalizedStringKey("payment.detail.events")) {
                if p.events.isEmpty {
                    Text(LocalizedStringKey("payment.detail.noEvents"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(p.events) { ev in eventRow(ev) }
                }
            }

            if !extras.isEmpty {
                Section(LocalizedStringKey("payment.detail.metadata")) {
                    ForEach(Array(extras.keys.sorted()), id: \.self) { key in
                        if let value = extras[key] {
                            LabeledContent(key, value: value)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder private func eventRow(_ ev: PaymentEventView) -> some View {
        // SDK 1.2's slim event shape: `kind` (event_type) + `occurredAt`. The
        // pre-1.2 source/prev/new fields aren't surfaced through the merchant
        // portal envelope anymore; the admin SPA / `/admin/payments/{id}`
        // route remains the full audit trail.
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(Color.accentColor).frame(width: 10, height: 10).padding(.top, 6)
            VStack(alignment: .leading, spacing: 3) {
                Text(humanize(ev.kind)).font(.subheadline.weight(.semibold))
                if let date = ISO.date(from: ev.occurredAt) {
                    Text(RelativeTime.string(for: date)).font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func humanize(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ".", with: " · ")
            .capitalized
    }
}
