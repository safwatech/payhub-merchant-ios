import SwiftUI

/// Full-screen gate shown over the main tab view while `LockManager.isLocked`.
/// Runs the biometric / device-passcode check on appear and on each "Unlock"
/// tap; the authenticated UI underneath is never reachable until it succeeds.
struct LockView: View {
    @EnvironmentObject private var lock: LockManager

    private var reason: String {
        NSLocalizedString("lock.reason", value: "Unlock PayHub Merchant to continue", comment: "Face ID / passcode prompt reason")
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            VStack(spacing: 16) {
                AppMarkView(size: 84)
                Text(AppInfo.name).font(.title3.weight(.semibold))
                Image(systemName: "lock.fill")
                    .font(.title)
                    .foregroundStyle(Brand.amber)
                    .padding(.top, 8)
                Text(LocalizedStringKey("lock.title"))
                    .font(.headline)
                Text(LocalizedStringKey("lock.subtitle"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
                Button {
                    Task { await lock.evaluate(reason: reason) }
                } label: {
                    Label(LocalizedStringKey("lock.unlock"), systemImage: "faceid")
                        .frame(maxWidth: 280)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 12)
            }
            .padding(32)
        }
        .task { await lock.evaluate(reason: reason) }
    }
}
