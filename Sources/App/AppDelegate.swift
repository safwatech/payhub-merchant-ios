import UIKit
import UserNotifications
import Sentry

/// Bridges the bits of UIKit SwiftUI doesn't surface: APNs token callbacks and
/// notification-tap handling. Wired via `@UIApplicationDelegateAdaptor`.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    /// Set by `PayHubMerchantApp` so notification taps can route through the app's router.
    weak var router: AppRouter?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        initCrashReporting()
        UNUserNotificationCenter.current().delegate = self
        // If the app was cold-launched from a notification, the tap is delivered
        // to `didReceive` after the scene connects — nothing to do here.
        return true
    }

    /// Crash / error reporting → GlitchTip (Sentry protocol). DSN injected at build
    /// time (`PAYHUB_SENTRY_DSN` → Info.plist → `AppInfo.sentryDSN`); empty ⇒ skip init
    /// entirely. No PII, crashes/errors only (no performance tracing).
    private func initCrashReporting() {
        let dsn = AppInfo.sentryDSN
        guard !dsn.isEmpty else { return }
        SentrySDK.start { options in
            options.dsn = dsn
            options.releaseName = "payhub-merchant-ios@\(AppInfo.version)"
            options.tracesSampleRate = 0.0
            options.enableAutoSessionTracking = true
            options.sendDefaultPii = false
            #if DEBUG
            options.environment = "debug"
            #else
            options.environment = "release"
            #endif
        }
    }

    // MARK: APNs token

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in PushManager.shared.didReceiveAPNsToken(deviceToken) }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in PushManager.shared.didFailToRegister(error) }
    }

    // MARK: Notification presentation / taps

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        // Show banners/sounds even when the app is foregrounded.
        [.banner, .sound, .badge]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        if let link = DeepLink.fromPushUserInfo(userInfo) {
            await MainActor.run { router?.handle(link) }
        }
    }
}
