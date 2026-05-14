import XCTest
import LocalAuthentication
import SwiftUI
@testable import PayHubMerchant

/// The biometric app lock's cold-start / background-timeout / enable-confirm logic
/// ([LockManager]) — exercised through a fake `DeviceAuthenticating` and a fake clock.
@MainActor
final class LockManagerTests: XCTestCase {

    private final class FakeAuthenticator: DeviceAuthenticating, @unchecked Sendable {
        var canAuth = true
        var nextResult = true
        var calls = 0
        func canAuthenticate() -> Bool { canAuth }
        // The protocol returns the `LAContext` that authenticated on success
        // so the LockManager can hand it to the Keychain — for tests, we
        // return a fresh context (its identity doesn't matter; the
        // Keychain in the test bundle has nothing to bind to).
        func authenticate(reason: String) async -> LAContext? {
            calls += 1
            return nextResult ? LAContext() : nil
        }
    }

    private func freshSettings(appLockEnabled: Bool = false) -> AppSettings {
        let defaults = UserDefaults(suiteName: "lockmgr-test-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        settings.appLockEnabled = appLockEnabled
        return settings
    }

    func testColdStartIsLockedOnlyWhenEnabled() {
        XCTAssertFalse(LockManager(settings: freshSettings(appLockEnabled: false), authenticator: FakeAuthenticator()).isLocked)
        let enabled = LockManager(settings: freshSettings(appLockEnabled: true), authenticator: FakeAuthenticator())
        XCTAssertTrue(enabled.isLocked)
        XCTAssertTrue(enabled.isEnabled)
    }

    func testCanEnableDelegatesToTheAuthenticator() {
        let auth = FakeAuthenticator()
        let m = LockManager(settings: freshSettings(), authenticator: auth)
        auth.canAuth = true
        XCTAssertTrue(m.canEnable)
        auth.canAuth = false
        XCTAssertFalse(m.canEnable)
    }

    func testBackgroundTimeoutRelocksOnlyAfterTheGraceWindow() async {
        var now = Date(timeIntervalSince1970: 10_000)
        let auth = FakeAuthenticator()
        let m = LockManager(settings: freshSettings(appLockEnabled: true), authenticator: auth, lockAfter: 120, now: { now })

        // Cold start → locked → unlock.
        XCTAssertTrue(m.isLocked)
        await m.evaluate(reason: "x")
        XCTAssertFalse(m.isLocked)

        // A quick glance at another app: under the window ⇒ no re-lock.
        m.handleScenePhase(.background)
        now = now.addingTimeInterval(60)
        m.handleScenePhase(.active)
        XCTAssertFalse(m.isLocked)

        // Backgrounded long enough ⇒ re-lock.
        m.handleScenePhase(.background)
        now = now.addingTimeInterval(121)
        m.handleScenePhase(.active)
        XCTAssertTrue(m.isLocked)
    }

    func testDisabledSessionNeverRelocks() {
        var now = Date(timeIntervalSince1970: 10_000)
        let m = LockManager(settings: freshSettings(appLockEnabled: false), authenticator: FakeAuthenticator(), lockAfter: 120, now: { now })
        m.handleScenePhase(.background)
        now = now.addingTimeInterval(10_000)
        m.handleScenePhase(.active)
        XCTAssertFalse(m.isLocked)
    }

    func testEvaluateUnlocksOnlyOnSuccess() async {
        let auth = FakeAuthenticator()
        let m = LockManager(settings: freshSettings(appLockEnabled: true), authenticator: auth)
        XCTAssertTrue(m.isLocked)

        auth.nextResult = false
        await m.evaluate(reason: "x")
        XCTAssertTrue(m.isLocked, "a failed/cancelled auth must leave the app locked")
        XCTAssertEqual(auth.calls, 1)

        auth.nextResult = true
        await m.evaluate(reason: "x")
        XCTAssertFalse(m.isLocked)
        XCTAssertEqual(auth.calls, 2)

        // Already unlocked ⇒ no further prompt.
        await m.evaluate(reason: "x")
        XCTAssertEqual(auth.calls, 2)
    }

    func testEnableRequiresConfirmation() async {
        let auth = FakeAuthenticator()
        let settings = freshSettings(appLockEnabled: false)
        let m = LockManager(settings: settings, authenticator: auth)

        // Cancelled the confirm prompt ⇒ stays off.
        auth.nextResult = false
        await m.setEnabled(true, confirmReason: "x")
        XCTAssertFalse(m.isEnabled)
        XCTAssertFalse(settings.appLockEnabled)

        // Confirmed ⇒ enabled, and it's a fresh unlock (no lock screen mid-session).
        auth.nextResult = true
        await m.setEnabled(true, confirmReason: "x")
        XCTAssertTrue(m.isEnabled)
        XCTAssertTrue(settings.appLockEnabled)
        XCTAssertFalse(m.isLocked)

        // Disabling needs no confirmation and clears any lock.
        await m.setEnabled(false, confirmReason: "x")
        XCTAssertFalse(m.isEnabled)
        XCTAssertFalse(settings.appLockEnabled)
        XCTAssertFalse(m.isLocked)
    }
}
