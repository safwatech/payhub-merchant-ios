import XCTest
import Payhub
@testable import PayHubMerchant

/// `/merchant/sub-merchants` + `.../users` raw-endpoint coverage.
final class MerchantRawAPISubMerchantsTests: XCTestCase {

    private let baseURL = URL(string: "https://app.payhub.test")!

    override func setUp() { super.setUp(); StubURLProtocol.reset() }
    override func tearDown() { StubURLProtocol.reset(); super.tearDown() }

    private func makeAPI() -> MerchantRawAPI {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        return MerchantRawAPI(baseURL: baseURL, accessTokenProvider: { "tok" },
                              session: URLSession(configuration: cfg))
    }

    // MARK: sub-merchants

    func testListSubMerchantsDecodesPaymentsCount() async throws {
        StubURLProtocol.stubs.append(.init(
            match: { $0.url?.path == "/merchant/sub-merchants" && $0.httpMethod == "GET" },
            response: { _ in (200, """
              [{
                "id":"s-1","merchant_id":"m-1","code":"acme-east","code_prefix":"AE",
                "name":"Acme East","status":"active","external_ref":"ext-9",
                "metadata":{"region":"east"},
                "created_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-02T00:00:00Z",
                "payments_count":7
              }]
            """) }))
        let subs = try await makeAPI().listSubMerchants()
        XCTAssertEqual(subs.count, 1)
        XCTAssertEqual(subs.first?.code, "acme-east")
        XCTAssertEqual(subs.first?.codePrefix, "AE")
        XCTAssertEqual(subs.first?.paymentsCount, 7)
        XCTAssertEqual(subs.first?.externalRef, "ext-9")
        XCTAssertEqual(subs.first?.metadata["region"]?.displayString, "east")
    }

    func testCreateSubMerchantPostsBody() async throws {
        StubURLProtocol.stubs.append(.init(
            match: { $0.url?.path == "/merchant/sub-merchants" && $0.httpMethod == "POST" },
            response: { _ in (201, """
              {"id":"s-2","merchant_id":"m-1","code":"acme-west","code_prefix":"AW","name":"Acme West",
               "status":"active","external_ref":null,"metadata":{},
               "created_at":"2026-01-03T00:00:00Z","updated_at":"2026-01-03T00:00:00Z","payments_count":0}
            """) }))
        let created = try await makeAPI().createSubMerchant(
            SubMerchantCreate(code: "acme-west", codePrefix: "AW", name: "Acme West", status: "active", externalRef: nil))
        XCTAssertEqual(created.code, "acme-west")
        let req = try XCTUnwrap(StubURLProtocol.recorded.last)
        let body = String(decoding: try XCTUnwrap(req.bodyData), as: UTF8.self)
        XCTAssertTrue(body.contains("\"code\":\"acme-west\""), body)
        XCTAssertTrue(body.contains("\"code_prefix\":\"AW\""), body)
        XCTAssertTrue(body.contains("\"status\":\"active\""), body)
        XCTAssertFalse(body.contains("external_ref"), body)   // nil → omitted
    }

    func testDeleteSubMerchant204Succeeds() async throws {
        StubURLProtocol.stubs.append(.init(
            match: { $0.url?.path == "/merchant/sub-merchants/s-1" && $0.httpMethod == "DELETE" },
            response: { _ in (204, "") }))
        try await makeAPI().deleteSubMerchant(id: "s-1")
        XCTAssertEqual(StubURLProtocol.recorded.last?.httpMethod, "DELETE")
    }

    func testDeleteSubMerchant409SurfacesPaymentsMessage() async {
        StubURLProtocol.stubs.append(.init(
            match: { $0.url?.path == "/merchant/sub-merchants/s-1" && $0.httpMethod == "DELETE" },
            response: { _ in (409, #"{"detail":"Sub-merchant has 3 payment(s); cannot delete. Disable it instead — set status to disabled."}"#) }))
        do {
            try await makeAPI().deleteSubMerchant(id: "s-1")
            XCTFail("expected throw")
        } catch {
            XCTAssertTrue(AppError.from(error).message.lowercased().contains("payment"), AppError.from(error).message)
        }
    }

    // MARK: sub-users

    func testListSubUsersDecodesRoleAndMfa() async throws {
        StubURLProtocol.stubs.append(.init(
            match: { $0.url?.path == "/merchant/sub-merchants/s-1/users" && $0.httpMethod == "GET" },
            response: { _ in (200, """
              [{"id":"u-1","sub_merchant_id":"s-1","username":"cashier1","role":"sub_operator",
                "status":"active","full_name":"Cashier One","email":"c1@acme.test","mobile":null,"phone":null,
                "mfa_enabled":true,"last_login_at":"2026-05-01T00:00:00Z","created_at":"2026-04-01T00:00:00Z"}]
            """) }))
        let users = try await makeAPI().listSubUsers(subID: "s-1")
        XCTAssertEqual(users.count, 1)
        XCTAssertEqual(users.first?.role, "sub_operator")
        XCTAssertTrue(users.first?.mfaEnabled ?? false)
        XCTAssertEqual(users.first?.email, "c1@acme.test")
    }

    func testCreateSubUserDecodesInviteURL() async throws {
        StubURLProtocol.stubs.append(.init(
            match: { $0.url?.path == "/merchant/sub-merchants/s-1/users" && $0.httpMethod == "POST" },
            response: { _ in (201, """
              {"id":"u-2","sub_merchant_id":"s-1","username":"cashier2","role":"sub_viewer","status":"active",
               "full_name":"Cashier Two","email":"c2@acme.test","mobile":null,"phone":null,
               "mfa_enabled":false,"last_login_at":null,"created_at":"2026-05-10T00:00:00Z",
               "invite_url":"https://app.payhub.test/m/accept-invite?token=abc&m=acme&u=cashier2&s=acme-east",
               "invite_sent_to_channel":"email","invite_expires_at":"2026-05-13T00:00:00Z"}
            """) }))
        let created = try await makeAPI().createSubUser(
            subID: "s-1",
            SubUserCreate(username: "cashier2", fullName: "Cashier Two", email: "c2@acme.test", mobile: nil, phone: nil, role: "sub_viewer"))
        XCTAssertTrue(created.inviteURL.contains("accept-invite"))
        XCTAssertEqual(created.inviteSentToChannel, "email")
        XCTAssertEqual(created.asSubUser.username, "cashier2")
        let body = String(decoding: try XCTUnwrap(StubURLProtocol.recorded.last?.bodyData), as: UTF8.self)
        XCTAssertTrue(body.contains("\"username\":\"cashier2\""), body)
        XCTAssertTrue(body.contains("\"role\":\"sub_viewer\""), body)
        XCTAssertFalse(body.contains("mobile"), body)   // nil → omitted
    }

    func testUpdateSubUser409LastOwnerSurfacesMessage() async {
        StubURLProtocol.stubs.append(.init(
            match: { $0.url?.path == "/merchant/sub-merchants/s-1/users/u-1" && $0.httpMethod == "PATCH" },
            response: { _ in (409, #"{"error":{"code":"hub.merchant.last_sub_owner","message":"That would leave the shop with no active owner."}}"#) }))
        do {
            _ = try await makeAPI().updateSubUser(subID: "s-1", uid: "u-1", SubUserPatch(role: "sub_viewer"))
            XCTFail("expected throw")
        } catch {
            let app = AppError.from(error)
            XCTAssertTrue(app.message.contains("no active owner"), app.message)
        }
    }

    func testClearSubUserMfaPostsCode() async throws {
        StubURLProtocol.stubs.append(.init(
            match: { $0.url?.path == "/merchant/sub-merchants/s-1/users/u-1/clear-mfa" && $0.httpMethod == "POST" },
            response: { _ in (204, "") }))
        try await makeAPI().clearSubUserMfa(subID: "s-1", uid: "u-1", code: "112233")
        let body = String(decoding: try XCTUnwrap(StubURLProtocol.recorded.last?.bodyData), as: UTF8.self)
        XCTAssertTrue(body.contains("\"code\":\"112233\""), body)
    }

    func testReissueInviteDecodes() async throws {
        StubURLProtocol.stubs.append(.init(
            match: { $0.url?.path == "/merchant/sub-merchants/s-1/users/u-1/reissue-invite" && $0.httpMethod == "POST" },
            response: { _ in (200, #"{"sent_to_channel":null,"invite_url":"https://app.payhub.test/m/accept-invite?token=zzz","expires_at":"2026-05-13T00:00:00Z"}"#) }))
        let r = try await makeAPI().reissueSubUserInvite(subID: "s-1", uid: "u-1")
        XCTAssertNil(r.sentToChannel)
        XCTAssertTrue(r.inviteURL.contains("accept-invite"))
    }
}
