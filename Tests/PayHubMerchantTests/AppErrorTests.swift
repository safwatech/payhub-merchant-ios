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

    func testMfaRequired401IsNotAuthFailure() {
        let pe = PayhubError.api(kind: .authentication, code: "hub.merchant.mfa_required", httpStatus: 401,
                                 message: "Authenticator code required.", details: [:], requestId: nil)
        let app = AppError.from(pe)
        XCTAssertFalse(app.isAuthFailure)
        XCTAssertTrue(app.requiresMFACode)
    }

    func testBadCredentials401IsNotAuthFailure() {
        let pe = PayhubError.api(kind: .authentication, code: "hub.merchant.bad_credentials", httpStatus: 401,
                                 message: "wrong", details: [:], requestId: nil)
        XCTAssertFalse(AppError.from(pe).isAuthFailure)
    }

    func testLastSubOwnerUsesServerMessage() {
        let pe = PayhubError.api(kind: .idempotencyConflict, code: "hub.merchant.last_sub_owner", httpStatus: 409,
                                 message: "That would leave the shop with no active owner.", details: [:], requestId: nil)
        let app = AppError.from(pe)
        XCTAssertTrue(app.message.contains("no active owner"))
    }

    func testLicenseLimitExceededSurfacesServerMessage() {
        let pe = PayhubError.api(kind: .permission, code: "hub.license.limit_exceeded", httpStatus: 403,
                                 message: "Sub-merchants aren't included in your plan — contact your vendor to upgrade.",
                                 details: [:], requestId: nil)
        let app = AppError.from(pe)
        XCTAssertTrue(app.message.contains("contact your vendor"))
        XCTAssertFalse(app.isAuthFailure)
    }

    // MARK: - SDK 1.2 typed errors

    func testMfaRequiredErrorIsStepUp() {
        let app = AppError.from(MfaRequiredError(message: "MFA needed"))
        XCTAssertFalse(app.isAuthFailure)
        XCTAssertTrue(app.isMfaRequired)
        XCTAssertEqual(app.code, "mfa_required")
    }

    func testMerchantValidationErrorCarriesCodeAndParams() {
        let v = MerchantValidationError(code: "merchant.locked_out",
                                         params: ["5m"], message: "Try again later")
        let app = AppError.from(v)
        XCTAssertEqual(app.code, "merchant.locked_out")
        XCTAssertEqual(app.params, ["5m"])
        XCTAssertFalse(app.isAuthFailure)
    }
}
