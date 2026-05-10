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
        XCTAssertNil(DeepLink.parse(URL(string: "https://app.payhub.ly/accept-invite?token=x")!))
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
