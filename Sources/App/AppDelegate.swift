import UIKit
import UserNotifications

/// Bridges the bits of UIKit SwiftUI doesn't surface: APNs token callbacks and
/// notification-tap handling. Wired via `@UIApplicationDelegateAdaptor`.
///
/// 0.4.0 note: crash reporting init moved out of `didFinishLaunching` and onto
/// `CrashReportingController.apply(enabled:)` (driven by `PayHubMerchantApp`
/// reacting to `AppSettings.crashReportingEnabled`). The toggle is off by
/// default — earlier releases unconditionally started Sentry on launch.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    /// Set by `PayHubMerchantApp` so notification taps can route through the app's router.
    weak var router: AppRouter?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // If the app was cold-launched from a notification, the tap is delivered
        // to `didReceive` after the scene connects — nothing to do here.
        return true
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
