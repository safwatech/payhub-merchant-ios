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
    /// Prompt with biometrics, falling back to the device passcode. `true` on success.
    func authenticate(reason: String) async -> Bool
}

/// Production `DeviceAuthenticating` backed by `LAContext` / `LAPolicy.deviceOwnerAuthentication`.
struct LAContextAuthenticator: DeviceAuthenticating {
    func canAuthenticate() -> Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }
    func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
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
    private var backgroundedAt: Date?
    private var evaluating = false

    init(settings: AppSettings = .shared,
         authenticator: DeviceAuthenticating = LAContextAuthenticator(),
         lockAfter: TimeInterval = 120,
         now: @escaping () -> Date = { Date() }) {
        self.settings = settings
        self.authenticator = authenticator
        self.lockAfter = lockAfter
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
        let ok = await authenticator.authenticate(reason: reason)
        evaluating = false
        if ok { isLocked = false }
    }

    /// Flip the feature. Enabling first confirms the user can authenticate (so they
    /// don't lock themselves out); if they cancel, the change is rejected and the
    /// observable state re-published so a bound `Toggle` snaps back. Enabling counts
    /// as a fresh unlock — no lock screen pops up mid-session.
    func setEnabled(_ enabled: Bool, confirmReason: String) async {
        if enabled, !(await authenticator.authenticate(reason: confirmReason)) {
            objectWillChange.send()   // bounce a bound Toggle back to "off"
            return
        }
        isEnabled = enabled
        settings.appLockEnabled = enabled
        if !enabled { isLocked = false }
    }
}
