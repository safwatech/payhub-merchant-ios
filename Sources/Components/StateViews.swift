import SwiftUI

/// Centered spinner with an optional caption — for full-screen / first loads.
struct LoadingView: View {
    var caption: String?

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            if let caption {
                Text(caption).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(caption ?? "Loading")
    }
}

/// A friendly error panel with an optional retry button.
struct ErrorStateView: View {
    let error: AppError
    var retry: (() -> Void)?

    var body: some View {
        ContentUnavailableViewCompat(
            title: error.title,
            systemImage: "exclamationmark.triangle",
            description: error.message + (error.requestId.map { "\n\nReference: \($0)" } ?? "")
        ) {
            if let retry, error.isRetryable {
                Button {
                    retry()
                } label: {
                    Label("Try again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

/// An empty-state panel.
struct EmptyStateView: View {
    let title: String
    let systemImage: String
    var description: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableViewCompat(title: title, systemImage: systemImage, description: description ?? "") {
            if let actionTitle, let action {
                Button(action: action) { Text(actionTitle) }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

/// A back-port of `ContentUnavailableView` for iOS 16 (it's iOS 17+).
struct ContentUnavailableViewCompat<Actions: View>: View {
    let title: String
    let systemImage: String
    let description: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            if !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            actions()
                .padding(.top, 4)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension ContentUnavailableViewCompat where Actions == EmptyView {
    init(title: String, systemImage: String, description: String) {
        self.init(title: title, systemImage: systemImage, description: description, actions: { EmptyView() })
    }
}
