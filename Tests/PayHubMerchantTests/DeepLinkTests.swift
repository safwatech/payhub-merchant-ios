import XCTest
@testable import PayHubMerchant

final class DeepLinkTests: XCTestCase {

    func testParseAcceptInvite() {
        let url = URL(string: "payhub://accept-invite?token=abc123&m=acme&u=boss&s=shop1")!
        guard case let .acceptInvite(token, m, u, s)? = DeepLink.parse(url) else {
            return XCTFail("expected acceptInvite")
        }
        XCTAssertEqual(token, "abc123")
        XCTAssertEqual(m, "acme")
        XCTAssertEqual(u, "boss")
        XCTAssertEqual(s, "shop1")
    }

    func testParseAcceptInviteMinimal() {
        let url = URL(string: "payhub://accept-invite?token=xyz")!
        guard case let .acceptInvite(token, m, u, s)? = DeepLink.parse(url) else {
            return XCTFail("expected acceptInvite")
        }
        XCTAssertEqual(token, "xyz")
        XCTAssertNil(m); XCTAssertNil(u); XCTAssertNil(s)
    }

    func testParseAcceptInviteRequiresToken() {
        XCTAssertNil(DeepLink.parse(URL(string: "payhub://accept-invite?m=acme")!))
    }

    func testParsePayLinkPath() {
        guard case let .payLink(id)? = DeepLink.parse(URL(string: "payhub://pay-link/pl_123")!) else {
            return XCTFail("expected payLink")
        }
        XCTAssertEqual(id, "pl_123")
    }

    func testParsePayLinkQuery() {
        guard case let .payLink(id)? = DeepLink.parse(URL(string: "payhub://pay-link?id=pl_456")!) else {
            return XCTFail("expected payLink")
        }
        XCTAssertEqual(id, "pl_456")
    }

    func testRejectsForeignScheme() {
        // A bare https://app.payhub.ly/accept-invite (without the /m/ prefix)
        // is intentionally NOT an invite — the live route is `/m/accept-invite`.
        XCTAssertNil(DeepLink.parse(URL(string: "https://app.payhub.ly/accept-invite?token=x")!))
        XCTAssertNil(DeepLink.parse(URL(string: "https://example.com/m/accept-invite?token=x")!))
    }

    // MARK: - Universal Links (0.4.0)

    func testParseHttpsAcceptInvite() {
        let url = URL(string: "https://app.payhub.ly/m/accept-invite?token=abc123&m=acme&u=boss&s=shop1")!
        guard case let .acceptInvite(token, m, u, s)? = DeepLink.parse(url) else {
            return XCTFail("expected acceptInvite")
        }
        XCTAssertEqual(token, "abc123")
        XCTAssertEqual(m, "acme")
        XCTAssertEqual(u, "boss")
        XCTAssertEqual(s, "shop1")
    }

    func testParseHttpsAcceptInviteMinimal() {
        let url = URL(string: "https://app.payhub.ly/m/accept-invite?token=xyz")!
        guard case let .acceptInvite(token, _, _, _)? = DeepLink.parse(url) else {
            return XCTFail("expected acceptInvite")
        }
        XCTAssertEqual(token, "xyz")
    }

    func testHttpsRequiresInvitePath() {
        // A stray https://app.payhub.ly URL that isn't the invite route
        // intentionally returns nil — the OS falls back to Safari.
        XCTAssertNil(DeepLink.parse(URL(string: "https://app.payhub.ly/some/marketing/page")!))
        XCTAssertNil(DeepLink.parse(URL(string: "https://app.payhub.ly/m/accept-invite")!))   // no token
    }

    func testParseInvitePureParser() {
        let url = URL(string: "https://app.payhub.ly/m/accept-invite?token=tk&m=ACME&u=alice&s=SH1")!
        let parsed = DeepLink.parseInvite(url)
        XCTAssertEqual(parsed?.token, "tk")
        XCTAssertEqual(parsed?.merchantCode, "ACME")
        XCTAssertEqual(parsed?.username, "alice")
        XCTAssertEqual(parsed?.subCode, "SH1")

        // Token-less invite URL → nil.
        XCTAssertNil(DeepLink.parseInvite(URL(string: "https://app.payhub.ly/m/accept-invite?m=ACME")!))
    }

    func testFromPushUserInfo() {
        let info: [AnyHashable: Any] = ["payhub": ["kind": "pay_link", "id": "pl_789"]]
        guard case let .payLink(id)? = DeepLink.fromPushUserInfo(info) else {
            return XCTFail("expected payLink")
        }
        XCTAssertEqual(id, "pl_789")
        XCTAssertNil(DeepLink.fromPushUserInfo(["unrelated": 1]))
    }
}
