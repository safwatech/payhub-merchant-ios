import SwiftUI

/// A small pill showing a pay-link status with an icon + tinted background.
struct StatusBadge: View {
    let status: PayLinkStatus
    var compact: Bool = false

    init(_ status: PayLinkStatus, compact: Bool = false) {
        self.status = status
        self.compact = compact
    }

    init(rawStatus: String, compact: Bool = false) {
        self.init(PayLinkStatus(rawString: rawStatus), compact: compact)
    }

    var body: some View {
        let color = Brand.statusColor(for: status)
        HStack(spacing: 4) {
            Image(systemName: status.systemImage)
                .imageScale(.small)
            if !compact {
                Text(status.label)
                    .font(.caption.weight(.semibold))
            }
        }
        .foregroundStyle(color)
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 3 : 4)
        .background(color.opacity(0.14), in: Capsule())
        .accessibilityLabel("Status: \(status.label)")
    }
}

/// A generic tinted text pill (used for role badges, entitlement chips, etc.).
struct TagPill: View {
    let text: String
    var systemImage: String?
    var color: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).imageScale(.small) }
            Text(text).font(.caption.weight(.semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.14), in: Capsule())
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        ForEach(PayLinkStatus.allCases, id: \.self) { StatusBadge($0) }
        TagPill(text: "Owner", systemImage: "person.badge.key", color: .indigo)
        TagPill(text: "Aggregator", systemImage: "building.2", color: .teal)
    }
    .padding()
}
