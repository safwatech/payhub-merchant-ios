import XCTest
import Payhub
@testable import PayHubMerchant

/// `/merchant/org` GET/PATCH coverage: full-field decode + sparse PATCH (only
/// dirty keys on the wire).
final class MerchantRawAPIOrgTests: XCTestCase {

    private let baseURL = URL(string: "https://app.payhub.test")!

    override func setUp() { super.setUp(); StubURLProtocol.reset() }
    override func tearDown() { StubURLProtocol.reset(); super.tearDown() }

    private func makeAPI() -> MerchantRawAPI {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        return MerchantRawAPI(baseURL: baseURL, accessTokenProvider: { "tok" },
                              session: URLSession(configuration: cfg))
    }

    private static let fullOrgJSON = """
      {
        "id": "org-1", "code": "acme", "name": "Acme Co", "type": "company",
        "status": "active", "created_at": "2026-01-02T03:04:05Z",
        "legal_name": "Acme Holdings Ltd", "tax_number": "TX-9", "commercial_register_no": "CR-77",
        "billing_email": "billing@acme.test", "support_email": "help@acme.test",
        "phone": "+218910000000", "website": "https://acme.test",
        "address_line_1": "1 Main St", "address_line_2": "Suite 2", "city": "Tripoli",
        "country": "LY", "logo_url": "https://acme.test/logo.png"
      }
    """

    func testGetOrgDecodesFullFieldSet() async throws {
        StubURLProtocol.stubs.append(.init(
            match: { $0.url?.path == "/merchant/org" && $0.httpMethod == "GET" },
            response: { _ in (200, Self.fullOrgJSON) }))
        let o = try await makeAPI().getOrg()
        XCTAssertEqual(o.code, "acme")
        XCTAssertEqual(o.name, "Acme Co")
        XCTAssertEqual(o.type, "company")
        XCTAssertEqual(o.legalName, "Acme Holdings Ltd")
        XCTAssertEqual(o.taxNumber, "TX-9")
        XCTAssertEqual(o.commercialRegisterNo, "CR-77")
        XCTAssertEqual(o.billingEmail, "billing@acme.test")
        XCTAssertEqual(o.supportEmail, "help@acme.test")
        XCTAssertEqual(o.phone, "+218910000000")
        XCTAssertEqual(o.website, "https://acme.test")
        XCTAssertEqual(o.addressLine1, "1 Main St")
        XCTAssertEqual(o.addressLine2, "Suite 2")
        XCTAssertEqual(o.city, "Tripoli")
        XCTAssertEqual(o.country, "LY")
        XCTAssertEqual(o.logoURL, "https://acme.test/logo.png")
    }

    func testUpdateOrgSendsOnlyDirtyKeys() async throws {
        StubURLProtocol.stubs.append(.init(
            match: { $0.url?.path == "/merchant/org" && $0.httpMethod == "PATCH" },
            response: { _ in (200, Self.fullOrgJSON) }))
        var patch = OrgPatch()
        patch.name = "Acme Renamed"
        patch.website = "https://renamed.test"
        let updated = try await makeAPI().updateOrg(patch)
        XCTAssertEqual(updated.code, "acme")   // round-trips the response

        let req = try XCTUnwrap(StubURLProtocol.recorded.last)
        XCTAssertEqual(req.httpMethod, "PATCH")
        let body = String(decoding: try XCTUnwrap(req.bodyData), as: UTF8.self)
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        XCTAssertEqual(Set(obj.keys), ["name", "website"])
        XCTAssertEqual(obj["name"] as? String, "Acme Renamed")
        XCTAssertEqual(obj["website"] as? String, "https://renamed.test")
    }
}
