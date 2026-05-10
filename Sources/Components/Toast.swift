import SwiftUI

/// A lightweight transient snackbar. Pass a `Toast?` binding; set it to show,
/// it auto-dismisses. Optionally carries a single inline action button.
struct Toast: Identifiable, Equatable {
    let id = UUID()
    let message: String
    var systemImage: String = "checkmark.circle.fill"
    var actionTitle: String?
    /// Compared by id only; the closure isn't part of equality.
    var action: (() -> Void)?

    static func == (lhs: Toast, rhs: Toast) -> Bool { lhs.id == rhs.id }
}

extension View {
    /// Overlays a toast at the bottom that auto-dismisses after `duration`.
    func toast(_ toast: Binding<Toast?>, duration: TimeInterval = 3.5) -> some View {
        modifier(ToastModifier(toast: toast, duration: duration))
    }
}

private struct ToastModifier: ViewModifier {
    @Binding var toast: Toast?
    let duration: TimeInterval

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let toast {
                    ToastBar(toast: toast) { self.toast = nil }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .task(id: toast.id) {
                            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                            withAnimation { if self.toast?.id == toast.id { self.toast = nil } }
                        }
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: toast)
    }
}

private struct ToastBar: View {
    let toast: Toast
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.systemImage)
                .foregroundStyle(Brand.amber)
            Text(toast.message)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
            Spacer(minLength: 4)
            if let title = toast.actionTitle, let action = toast.action {
                Button(title) { action(); dismiss() }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(Brand.amber)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .frame(maxWidth: 460)
    }
}
