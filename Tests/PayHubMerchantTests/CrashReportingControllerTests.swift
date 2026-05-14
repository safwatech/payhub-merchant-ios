import XCTest
@testable import PayHubMerchant

@MainActor
final class CrashReportingControllerTests: XCTestCase {

    func testNoDsnIsAvailableFalse() {
        let c = CrashReportingController(dsn: "", releaseVersion: "0.4.0", environment: "test")
        XCTAssertFalse(c.isAvailable)
    }

    func testDsnSetIsAvailableTrue() {
        let c = CrashReportingController(dsn: "https://x@example.com/1", releaseVersion: "0.4.0", environment: "test")
        XCTAssertTrue(c.isAvailable)
    }

    func testApplyShortCircuitsWhenDsnEmpty() {
        // No DSN baked in → `apply` increments the counter (so we know we
        // were called) but doesn't reach into SentrySDK. Side-effect-free in
        // the test runner — passing implicitly means no crash.
        let c = CrashReportingController(dsn: "", releaseVersion: "0.4.0", environment: "test")
        c.apply(enabled: true)
        c.apply(enabled: false)
        XCTAssertEqual(c.applyCount, 2)
        XCTAssertEqual(c.lastAppliedValue, false)
    }

    func testApplyTracksLastValue() {
        let c = CrashReportingController(dsn: "", releaseVersion: "0.4.0", environment: "test")
        c.apply(enabled: true)
        XCTAssertEqual(c.lastAppliedValue, true)
        c.apply(enabled: false)
        XCTAssertEqual(c.lastAppliedValue, false)
    }
}
