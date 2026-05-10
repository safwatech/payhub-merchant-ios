import SwiftUI

/// A dashboard metric card: an icon, a big number, a label, and an optional
/// secondary line (e.g. money volume). Tappable when `action` is provided.
struct CounterCard: View {
    let title: String
    let value: String
    var subtitle: String?
    let systemImage: String
    var tint: Color = Brand.amber
    var action: (() -> Void)?

    var body: some View {
        let content = VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: systemImage)
                    .font(.headline)
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Spacer()
                if action != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            Text(value)
                .font(.system(.title, design: .rounded).weight(.bold))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }
}

#Preview {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
        CounterCard(title: "Paid", value: "12", subtitle: "54.500 LYD", systemImage: "checkmark.circle.fill", tint: .green) {}
        CounterCard(title: "In flight", value: "3", systemImage: "clock.fill", tint: .orange)
        CounterCard(title: "Active pay-links", value: "7", systemImage: "link", tint: .blue)
        CounterCard(title: "Needs follow-up", value: "2", systemImage: "bell.badge", tint: .pink)
    }
    .padding()
    .background(Color(uiColor: .systemGroupedBackground))
}
