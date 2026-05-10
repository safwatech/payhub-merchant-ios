import SwiftUI
import Payhub

/// A header card identifying who you're signed in as: merchant (and shop) name
/// + a role badge. Sits at the top of the Dashboard.
struct BrandHeader: View {
    let me: MerchantMe

    var body: some View {
        HStack(spacing: 14) {
            AppMarkView(size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(me.merchant.name)
                    .font(.headline)
                    .lineLimit(1)
                if let sub = me.subMerchant {
                    Text("Shop: \(sub.name) (\(sub.code))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(me.merchant.code)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            TagPill(text: roleLabel(me.effectiveRole),
                    systemImage: "person.badge.key",
                    color: Brand.roleColor(for: me.effectiveRole))
        }
        .padding(16)
        .background(Brand.amberSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// A non-dismissable inline banner used for read-only / degraded notices.
struct InfoBanner: View {
    let text: String
    var systemImage: String = "info.circle"
    var color: Color = .secondary

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage).foregroundStyle(color)
            Text(text).font(.footnote).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
