import XCTest
@testable import PayHubMerchant

/// Behavioural tests for the biometric-bound refresh-token Keychain item.
/// Each test runs against a per-test `service` so concurrent / leftover items
/// don't bleed across runs; the access-control path is exercised only when
/// the simulator's keychain accepts the flags (it usually does, but a
/// missing-passcode device falls back to the plain `afterFirstUnlock` mode,
/// which `write` handles defensively).
@MainActor
final class RefreshTokenVaultTests: XCTestCase {

    private func newVault(lockEnabled: Bool) -> RefreshTokenVault {
        let svc = "ly.payhub.merchant.tests.\(UUID().uuidString)"
        return RefreshTokenVault(service: svc, account: "refresh-token", isLockEnabled: { lockEnabled })
    }

    func testRoundTripLockOff() {
        let v = newVault(lockEnabled: false)
        v.delete()
        v.write("rt_aaa")
        XCTAssertEqual(v.read(), "rt_aaa")
        v.delete()
        XCTAssertNil(v.read())
    }

    func testDeleteIsIdempotent() {
        let v = newVault(lockEnabled: false)
        v.delete()
        v.delete()  // no crash
        XCTAssertNil(v.read())
    }

    func testWriteReplacesExisting() {
        let v = newVault(lockEnabled: false)
        v.write("first")
        v.write("second")
        XCTAssertEqual(v.read(), "second")
        v.delete()
    }

    func testRewrapNoOpOnEmpty() {
        let v = newVault(lockEnabled: false)
        v.delete()
        v.rewrap()   // nothing stored — must not crash
        XCTAssertNil(v.read())
    }

    func testRewrapPreservesTokenAcrossModeFlip() {
        // The simulator's keychain may refuse a biometric access-control on a
        // no-passcode device — the vault falls back to `afterFirstUnlock` in
        // that case, so the round-trip still works. We're verifying the
        // **token value survives** the rewrap, not the OS gate (which needs
        // a hardware test).
        let store = NSMutableDictionary()
        var lockOn = false
        let svc = "ly.payhub.merchant.tests.\(UUID().uuidString)"
        let v = RefreshTokenVault(service: svc, account: "refresh-token",
                                    isLockEnabled: { lockOn })
        v.write("rt_persists")
        XCTAssertEqual(v.read(), "rt_persists")

        // Flip to "lock on" and rewrap — the same value should still be
        // readable on the same device in the same test run.
        lockOn = true
        v.rewrap()
        XCTAssertEqual(v.read(), "rt_persists")

        // And back.
        lockOn = false
        v.rewrap()
        XCTAssertEqual(v.read(), "rt_persists")
        v.delete()
        _ = store    // keep the variable to silence the unused warning
    }
}
