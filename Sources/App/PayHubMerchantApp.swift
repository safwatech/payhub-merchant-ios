import SwiftUI

/// "PayHub Merchant" — the native iOS companion app for PayHub merchants.
/// Sign in, watch the dashboard, create and follow up on pay-links, manage push.
@main
struct PayHubMerchantApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var settings = AppSettings.shared
    @StateObject private var repository = MerchantRepository()
    @StateObject private var router = AppRouter()
    @StateObject private var lock = LockManager()

    /// Runtime-gated crash reporting. Off until both the build-time DSN is
    /// non-empty **and** the More → Diagnostics toggle is on.
    private let crashReporting = CrashReportingController()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(repository)
                .environmentObject(router)
                .environmentObject(lock)
                .tint(Brand.amber)
                .task {
                    // Apply the persisted crash-reporting preference exactly
                    // once at launch — flips on if it was on, no-op otherwise.
                    crashReporting.apply(enabled: settings.crashReportingEnabled)
                    // Wire the delegate ↔ router/push, then validate the persisted session.
                    appDelegate.router = router
                    PushManager.shared.repository = repository
                    await PushManager.shared.refreshAuthorizationStatus()
                    await repository.bootstrap()
                }
                .onChange(of: settings.crashReportingEnabled) { newValue in
                    crashReporting.apply(enabled: newValue)
                }
                .onOpenURL { url in router.handleURL(url) }
                // Universal Links (0.4.0): `https://app.payhub.ly/m/accept-invite?…`
                // arrives via NSUserActivity, not `onOpenURL`. The hostname is
                // pinned in `apple-app-site-association` on the server and again
                // in the `applinks:app.payhub.ly` entitlement, so DeepLink.parse
                // only has to discriminate accept-invite vs. ignore.
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { router.handleURL(url) }
                }
                .onChange(of: scenePhase) { phase in lock.handleScenePhase(phase) }
        }
    }
}
