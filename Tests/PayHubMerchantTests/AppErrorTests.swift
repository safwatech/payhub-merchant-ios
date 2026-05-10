import XCTest
import Payhub
@testable import PayHubMerchant

final class AppErrorTests: XCTestCase {

    func testAuthenticationMapsToAuthFailure() {
        let pe = PayhubError.api(kind: .authentication, code: "hub.auth.expired", httpStatus: 401,
                                 message: "expired", details: [:], requestId: "req-1")
        let app = AppError.from(pe)
        XCTAssertTrue(app.isAuthFailure)
        XCTAssertEqual(app.requestId, "req-1")
    }

    func testRateLimitedIsRetryable() {
        let pe = PayhubError.api(kind: .rateLimited(retryAfter: 5), code: "hub.rate", httpStatus: 429,
                                 message: "slow down", details: [:], requestId: nil)
        let app = AppError.from(pe)
        XCTAssertTrue(app.isRetryable)
        XCTAssertFalse(app.isAuthFailure)
    }

    func testValidationUsesFriendlyMessageForKnownCode() {
        let pe = PayhubError.api(kind: .validation, code: "hub.sub_merchant.ref_too_long", httpStatus: 422,
                                 message: "too long", details: [:], requestId: nil)
        let app = AppError.from(pe)
        XCTAssertTrue(app.message.lowercased().contains("too long"))
        XCTAssertEqual(app.title, "Check your input")
    }

    func testTransportTimeoutRetryable() {
        let app = AppError.from(PayhubError.transport(kind: .timeout, message: "deadline"))
        XCTAssertTrue(app.isRetryable)
        XCTAssertEqual(app.title, "Timed out")
    }

    func testServerErrorRetryable() {
        let pe = PayhubError.api(kind: .server, code: "hub.boom", httpStatus: 503,
                                 message: "down", details: [:], requestId: nil)
        XCTAssertTrue(AppError.from(pe).isRetryable)
    }

    func testPassthroughForExistingAppError() {
        let original = AppError(title: "T", message: "M", isRetryable: true)
        let mapped = AppError.from(original)
        XCTAssertEqual(mapped.title, "T")
        XCTAssertEqual(mapped.message, "M")
        XCTAssertTrue(mapped.isRetryable)
    }
}
