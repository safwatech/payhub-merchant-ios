import SwiftUI

/// The PayHub mark, drawn programmatically (no asset dependency at this size):
/// an amber rounded square with a stylised "hub" glyph. Used on the launch and
/// login screens. The app icon itself is the real brand PNG in the asset catalog.
struct AppMarkView: View {
    var size: CGFloat = 72

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(
                    LinearGradient(colors: [Brand.amber, Brand.amberDeep],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(90))
        }
        .frame(width: size, height: size)
        .shadow(color: Brand.amber.opacity(0.35), radius: size * 0.12, y: size * 0.05)
        .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: 24) {
        AppMarkView(size: 48)
        AppMarkView(size: 96)
    }
    .padding()
}
