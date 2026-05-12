import XCTest
import Payhub
@testable import PayHubMerchant

/// `MerchantMe` visibility helpers (`isParent` / `isParentOwner` / `canManageSubs`).
final class MerchantMeRolesTests: XCTestCase {

    private func me(_ json: String) throws -> MerchantMe {
        try JSONDecoder().decode(MerchantMe.self, from: Data(json.utf8))
    }

    private func base(role: String, effectiveRole: String, sub: Bool, aggregator: Bool) -> String {
        let subJSON = sub ? #","sub_merchant":{"id":"s-1","code":"east","code_prefix":"AE","name":"East"}"# : ""
        return """
        {"id":"u-1","username":"boss","role":"\(role)","effective_role":"\(effectiveRole)","full_name":"Boss",
         "email":null,"mobile":null,"mfa_enabled":false,
         "merchant":{"id":"m-1","code":"acme","name":"Acme","type":"company"},
         "entitlements":{"aggregator":\(aggregator),"smart_routing":false,"pay_link_quota":5}\(subJSON)}
        """
    }

    func testParentOwnerWithAggregator() throws {
        let m = try me(base(role: "owner", effectiveRole: "owner", sub: false, aggregator: true))
        XCTAssertTrue(m.isParent)
        XCTAssertTrue(m.isParentOwner)
        XCTAssertTrue(m.canManageSubs)
    }

    func testParentOwnerWithoutAggregator() throws {
        let m = try me(base(role: "owner", effectiveRole: "owner", sub: false, aggregator: false))
        XCTAssertTrue(m.isParentOwner)
        XCTAssertFalse(m.canManageSubs)
    }

    func testParentNonOwner() throws {
        let m = try me(base(role: "viewer", effectiveRole: "viewer", sub: false, aggregator: true))
        XCTAssertTrue(m.isParent)
        XCTAssertFalse(m.isParentOwner)
        XCTAssertFalse(m.canManageSubs)
    }

    func testLicenseDowngradeUsesEffectiveRole() throws {
        // role says owner but the effective role collapsed → not a parent owner.
        let m = try me(base(role: "owner", effectiveRole: "viewer", sub: false, aggregator: true))
        XCTAssertFalse(m.isParentOwner)
        XCTAssertFalse(m.canManageSubs)
    }

    func testSubUserNeverParent() throws {
        let m = try me(base(role: "sub_owner", effectiveRole: "sub_owner", sub: true, aggregator: true))
        XCTAssertFalse(m.isParent)
        XCTAssertFalse(m.isParentOwner)
        XCTAssertFalse(m.canManageSubs)
    }
}
