import XCTest
import Payhub
@testable import PayHubMerchant

/// Coverage for the change-password / MFA raw endpoints + the 401-special-case
/// envelope handling (a 401 here is "wrong password / code", not session loss).
final class MerchantRawAPIAuthTests: XCTestCase {

    private let baseURL = URL(string: "https://app.payhub.test")!
    private let bearer = "test-access-token"

    override func setUp() { super.setUp(); StubURLProtocol.reset() }
    override func tearDown() { StubURLProtocol.reset(); super.tearDown() }

    private func makeAPI() -> MerchantRawAPI {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        let token = bearer
        return MerchantRawAPI(baseURL: baseURL, accessTokenProvider: { token },
                              session: URLSession(configuration: cfg))
    }

    private func bodyString(_ req: URLRequest) throws -> String {
        let data = try XCTUnwrap(req.bodyData)
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: change-password

    func testChangePasswordPostsExpectedBody() async throws {
        StubURLProtocol.stubs.append(.init(
            match: { $0.url?.path == "/merchant/auth/change-password" },
            response: { _ in (204, "") }))
        try await makeAPI().changePassword(oldPassword: "old-secret-12", newPassword: "new-secret-1234", code: "123456")
        let req = try XCTUnwrap(StubURLProtocol.recorded.last)
        XCTAssertEqual(req.httpMethod, "POST")
        let body = try bodyString(req)
        XCTAssertTrue(body.contains("\"old_password\":\"old-secret-12\""), body)
        XCTAssertTrue(body.contains("\"new_password\":\"new-secret-1234\""), body)
        XCTAssertTrue(body.contains("\"code\":\"123456\""), body)
    }

    func testChangePasswordOmitsCodeWhenNil() async throws {
        StubURLProtocol.stubs.append(.init(
            match: { $0.url?.path == "/merchant/auth/change-password" },
            response: { _ in (204, "") }))
        try await makeAPI().changePassword(oldPassword: "old", newPassword: "new-secret-1234", code: nil)
        let body = try bodyString(try XCTUnwrap(StubURLProtocol.recorded.last))
        XCTAssertFalse(body.contains("code"), body)
    }

    func testMfaRequired401IsNotAuthFailure() async {
        StubURLProtocol.stubs.append(.init(
            match: { $0.url?.path == "/merchant/auth/change-password" },
            response: { _ in (401, #"{"error":{"code":"hub.merchant.mfa_required","message":"Authenticator code required."}}"#) }))
        do {
            try await makeAPI().changePassword(oldPassword: "old", newPassword: "new-secret-1234", code: nil)
            XCTFail("expected throw")
        } catch {
            let app = AppError.from(error)
            XCTAssertFalse(app.isAuthFailure, "mfa_required must not flag a session loss")
        }
    }

    func testBadCredentials401IsNotAuthFailure() async {
        StubURLProtocol.stubs.append(.init(
            match: { $0.url?.path == "/merchant/auth/change-password" },
            response: { _ in (401, #"{"error":{"code":"hub.merchant.bad_credentials","message":"wrong"}}"#) }))
        do {
            try await makeAPI().changePassword(oldPassword: "wrong", newPassword: "new-secret-1234", code: nil)
            XCTFail("expected throw")
        } catch {
            XCTAssertFalse(AppError.from(error).isAuthFailure)
        }
    }

    func testExpired401StillFlagsAuthFailure() async {
        StubURLProtocol.stubs.append(.init(
            match: { _ in true },
            response: { _ in (401, #"{"error":{"code":"hub.auth.expired","message":"expired"}}"#) }))
        do {
            _ = try await makeAPI().getOrg()
            XCTFail("expected throw")
        } catch {
            XCTAssertTrue(AppError.from(error).isAuthFailure)
        }
    }

    // MARK: MFA enrol / confirm / disable

    func testMfaEnrolDecodesSecretAndURI() async throws {
        StubURLProtocol.stubs.append(.init(
            match: { $0.url?.path == "/merchant/auth/mfa/enrol" },
            response: { _ in (200, """
              {"secret":"JBSWY3DPEHPK3PXP","otpauth_uri":"otpauth://totp/PayHub:boss?secret=JBSWY3DPEHPK3PXP&issuer=PayHub","issuer":"PayHub","account":"boss"}
            """) }))
        let e = try await makeAPI().mfaEnrol()
        XCTAssertEqual(e.secret, "JBSWY3DPEHPK3PXP")
        XCTAssertTrue(e.otpauthURI.hasPrefix("otpauth://totp/"))
        XCTAssertEqual(e.issuer, "PayHub")
        XCTAssertEqual(e.account, "boss")
        let req = try XCTUnwrap(StubURLProtocol.recorded.last)
        XCTAssertEqual(req.httpMethod, "POST")
    }

    func testMfaConfirmPostsCode() async throws {
        StubURLProtocol.stubs.append(.init(
            match: { $0.url?.path == "/merchant/auth/mfa/confirm" },
            response: { _ in (204, "") }))
        try await makeAPI().mfaConfirm(code: "654321")
        let body = try bodyString(try XCTUnwrap(StubURLProtocol.recorded.last))
        XCTAssertTrue(body.contains("\"code\":\"654321\""), body)
    }

    func testMfaDisablePostsPassword() async throws {
        StubURLProtocol.stubs.append(.init(
            match: { $0.url?.path == "/merchant/auth/mfa/disable" },
            response: { _ in (204, "") }))
        try await makeAPI().mfaDisable(password: "pw-12chars-ok")
        let body = try bodyString(try XCTUnwrap(StubURLProtocol.recorded.last))
        XCTAssertTrue(body.contains("\"password\":\"pw-12chars-ok\""), body)
    }

    func testMfaNotEnabled409SurfacesServerMessage() async {
        StubURLProtocol.stubs.append(.init(
            match: { $0.url?.path == "/merchant/auth/mfa/disable" },
            response: { _ in (409, #"{"error":{"code":"hub.merchant.mfa_not_enabled","message":"MFA is not currently enabled."}}"#) }))
        do {
            try await makeAPI().mfaDisable(password: "pw")
            XCTFail("expected throw")
        } catch let pe as PayhubError {
            guard case let .api(_, code, _, _, _, _) = pe else { return XCTFail("got \(pe)") }
            XCTAssertEqual(code, "hub.merchant.mfa_not_enabled")
        } catch { XCTFail("unexpected: \(error)") }
    }

    func testDetailOnlyEnvelopeFallback() async {
        // FastAPI HTTPException shape: `{"detail": "..."}` — message must not be swallowed.
        StubURLProtocol.stubs.append(.init(
            match: { $0.url?.path == "/merchant/org" },
            response: { _ in (400, #"{"detail":"no fields to update"}"#) }))
        do {
            _ = try await makeAPI().updateOrg(OrgPatch())
            XCTFail("expected throw")
        } catch {
            XCTAssertTrue(AppError.from(error).message.lowercased().contains("no fields"), AppError.from(error).message)
        }
    }
}
