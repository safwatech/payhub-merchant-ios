import Foundation
import UIKit
import UserNotifications
import Combine

/// Coordinates remote-notification registration with the backend.
///
/// Flow:
///   1. User flips the "Push notifications" toggle in **More** → `enable()`.
///   2. `enable()` asks `UNUserNotificationCenter` for authorization, then calls
///      `UIApplication.shared.registerForRemoteNotifications()`.
///   3. `AppDelegate.didRegisterForRemoteNotificationsWithDeviceToken` hands the
///      APNs token back here via `didReceiveAPNsToken(_:)`, which (if logged in)
///      POSTs it to `/merchant/devices`.
///   4. Toggle-off → `disable()` → `DELETE /merchant/devices` (token in the body).
///
/// APNs prerequisites (provisioning, not in this repo): an App ID with the
/// "Push Notifications" capability and an APNs auth key `.p8` configured on the
/// PayHub server (`_ApnsNotifier`). Placeholders only here.
@MainActor
final class PushManager: ObservableObject {
    static let shared = PushManager()

    /// Granted-or-not, surfaced to the More screen for the toggle's truth.
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    /// Last APNs token we saw this launch (hex), so toggle-off can unregister it.
    private var lastTokenHex: String?

    /// Set by the app once the repository exists, so push registration can reach it.
    weak var repository: MerchantRepository?

    private init() {}

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    /// Request authorization (if needed) and kick off APNs registration.
    /// Returns true if we ended up authorized.
    @discardableResult
    func enable() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        await refreshAuthorizationStatus()
        guard granted else { return false }
        UIApplication.shared.registerForRemoteNotifications()
        return true
    }

    /// Stop receiving pushes: tell the backend to forget this device token.
    func disable() async {
        guard let token = lastTokenHex, let repo = repository else { return }
        try? await repo.unregisterDevice(apnsTokenHex: token)
        // (We deliberately don't call `unregisterForRemoteNotifications()` — the
        //  OS keeps the token; the server simply won't target it anymore.)
    }

    /// Called from `AppDelegate` once iOS hands us a device token.
    func didReceiveAPNsToken(_ deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        lastTokenHex = hex
        Task {
            guard AppSettings.shared.pushEnabled, let repo = repository else { return }
            try? await repo.registerDevice(apnsTokenHex: hex)
        }
    }

    func didFailToRegister(_ error: Error) {
        // Non-fatal — log only. Common on simulators without a push profile.
        #if DEBUG
        print("[PushManager] APNs registration failed: \(error)")
        #endif
    }
}
