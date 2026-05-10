import SwiftUI
import Payhub

/// One row in the pay-links list: order ref (monospaced), amount, status badge,
/// relative expiry, attempts, and extend/reshare counters.
struct PayLinkRow: View {
    let link: PayLink

    private var status: PayLinkStatus { PayLinkStatus(rawString: link.status) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(link.merchantOrderRef)
                    .font(.system(.subheadline, design: .monospaced).weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Text(Money.format(minor: link.amountMinor, currency: link.currency))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }

            HStack(spacing: 8) {
                StatusBadge(status)
                if let expiry = RelativeTime.expiry(link.expiresAt), status == .active {
                    Label(expiry, systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                metaChips
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var metaChips: some View {
        HStack(spacing: 8) {
            Label("\(link.attempts)/5", systemImage: "arrow.triangle.2.circlepath")
                .labelStyle(.titleAndIcon)
            if link.extendCount > 0 {
                Label("\(link.extendCount)", systemImage: "calendar.badge.plus")
            }
            if link.resharedCount > 0 {
                Label("\(link.resharedCount)", systemImage: "square.and.arrow.up")
            }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .imageScale(.small)
    }
}
