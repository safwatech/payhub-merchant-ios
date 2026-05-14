import Foundation
import Combine
import SwiftUI
import LocalAuthentication

/// Abstraction over the platform biometric / device-credential check, so
/// [LockManager] can be unit-tested without a real `LAContext`.
protocol DeviceAuthenticating: Sendable {
    /// True if the device has a biometric *or* a passcode enrolled — i.e. there's
    /// something to authenticate against.
    func canAuthenticate() -> Bool
    /// Prompt with biometrics, falling back to the device passcode. Returns
    /// the `LAContext` that handled the evaluate on success (so callers can
    /// hand it to the Keychain for the same OS-cached-auth window) and `nil`
    /// on cancel / failure.
    func authenticate(reason: String) async -> LAContext?
}

/// Production `DeviceAuthenticating` backed by `LAContext` / `LAPolicy.deviceOwnerAuthentication`.
struct LAContextAuthenticator: DeviceAuthenticating {
    func canAuthenticate() -> Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }
    func authenticate(reason: String) async -> LAContext? {
        let context = LAContext()
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
                continuation.resume(returning: success ? context : nil)
            }
        }
    }
}

/// The biometric / device-credential app lock.
///
/// When [isEnabled] (persisted via [AppSettings.appLockEnabled]), the
/// authenticated UI is gated behind a Face ID / Touch ID / device-passcode
/// prompt on cold start and whenever the app returns to the foreground after
/// more than `lockAfter` in the background. The view layer shows the lock screen
/// reactively on `isLocked` and drives the prompt via [evaluate].
///
/// It's a defence-in-depth + UX layer over the (already Keychain-resident) token
/// pair — it does not by itself bind the token to the biometric key.
@MainActor
final class LockManager: ObservableObject {

    /// `true` ⇒ show the lock screen (only ever set while the feature is enabled).
    @Published private(set) var isLocked: Bool
    /// Mirrors [AppSettings.appLockEnabled] so SwiftUI bindings observe it.
    @Published private(set) var isEnabled: Bool

    private let settings: AppSettings
    private let authenticator: DeviceAuthenticating
    private let lockAfter: TimeInterval
    private let now: () -> Date
    private let tokenStore: KeychainTokenStore
    private var backgroundedAt: Date?
    private var evaluating = false

    init(settings: AppSettings = .shared,
         authenticator: DeviceAuthenticating = LAContextAuthenticator(),
         lockAfter: TimeInterval = 120,
         tokenStore: KeychainTokenStore = .shared,
         now: @escaping () -> Date = { Date() }) {
        self.settings = settings
        self.authenticator = authenticator
        self.lockAfter = lockAfter
        self.tokenStore = tokenStore
        self.now = now
        self.isEnabled = settings.appLockEnabled
        self.isLocked = settings.appLockEnabled   // cold start → locked iff enabled
    }

    /// Whether the toggle in More → Security should be offered (a credential is enrolled).
    var canEnable: Bool { authenticator.canAuthenticate() }

    /// Wire `@Environment(\.scenePhase)` to this from the App.
    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            backgroundedAt = now()
        case .active:
            if isEnabled, let since = backgroundedAt, now().timeIntervalSince(since) > lockAfter {
                isLocked = true
            }
        case .inactive:
            break          // also the transient state while the Face ID sheet is up — don't stamp
        @unknown default:
            break
        }
    }

    /// Run the biometric / device-credential check; unlock on success. Re-entrant-safe
    /// (a fast double-tap won't stack two prompts). Called by the lock screen on appear
    /// and on the "Unlock" button.
    func evaluate(reason: String) async {
        guard isLocked, !evaluating else { return }
        evaluating = true
        let context = await authenticator.authenticate(reason: reason)
        evaluating = false
        if let context {
            // Bind the freshly-evaluated context to the refresh-token vault so
            // the SDK's first 401-refresh-retry within the OS's ~5s cached-auth
            // window doesn't pop a second prompt for the user.
            tokenStore.bind(authenticationContext: context)
            isLocked = false
        }
    }

    /// Flip the feature. Enabling first confirms the user can authenticate (so they
    /// don't lock themselves out); if they cancel, the change is rejected and the
    /// observable state re-published so a bound `Toggle` snaps back. Enabling counts
    /// as a fresh unlock — no lock screen pops up mid-session.
    ///
    /// After persisting the new value, the refresh-token-at-rest is rewrapped
    /// (lock-on → biometric-gated Keychain item; lock-off → plain
    /// `afterFirstUnlock`). A bound LAContext from the just-completed evaluate
    /// is handed to the vault so the rewrap doesn't itself re-prompt.
    func setEnabled(_ enabled: Bool, confirmReason: String) async {
        if enabled {
            guard let context = await authenticator.authenticate(reason: confirmReason) else {
                objectWillChange.send()   // bounce a bound Toggle back to "off"
                return
            }
            tokenStore.bind(authenticationContext: context)
        }
        isEnabled = enabled
        settings.appLockEnabled = enabled
        // Rewrap reads the refresh-token through the just-bound context and
        // re-writes it with the new access-control shape — one prompt
        // amortised across the toggle.
        tokenStore.rewrapRefreshToken()
        if !enabled { isLocked = false }
    }
}
