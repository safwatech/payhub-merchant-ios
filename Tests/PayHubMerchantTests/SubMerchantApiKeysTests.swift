import XCTest
import Payhub
@testable import PayHubMerchant

@MainActor
final class SubMerchantApiKeysTests: XCTestCase {

    func testScopesParsingCommaAndWhitespace() {
        let vm = SubMerchantApiKeysViewModel(subID: "sm_1")
        vm.createScopesText = "payments.write, payments.read settlements.read"
        XCTAssertEqual(vm.scopes, ["payments.write", "payments.read", "settlements.read"])
    }

    func testEmptyScopesBlocksCreate() {
        let vm = SubMerchantApiKeysViewModel(subID: "sm_1")
        vm.createScopesText = ""
        XCTAssertFalse(vm.canCreate)
    }

    func testNonEmptyScopesUnblocksCreate() {
        let vm = SubMerchantApiKeysViewModel(subID: "sm_1")
        vm.createScopesText = "payments.write"
        XCTAssertTrue(vm.canCreate)
    }

    func testAllowedIpsParsing() {
        let vm = SubMerchantApiKeysViewModel(subID: "sm_1")
        vm.createAllowedIpsText = "10.0.0.1, 10.0.0.2"
        XCTAssertEqual(vm.allowedIps, ["10.0.0.1", "10.0.0.2"])
    }

    func testEmptyAllowedIpsAreEmpty() {
        let vm = SubMerchantApiKeysViewModel(subID: "sm_1")
        vm.createAllowedIpsText = ""
        XCTAssertTrue(vm.allowedIps.isEmpty)
    }

    func testRevealedKeyWireFormat() {
        let r = SubMerchantApiKeysViewModel.RevealedKey(
            id: "rec_1", keyId: "phk_abc", secret: "shhh")
        XCTAssertEqual(r.wireFormat, "phk_abc.shhh")
    }

    func testDismissRevealClearsState() {
        let vm = SubMerchantApiKeysViewModel(subID: "sm_1")
        vm.revealedKey = .init(id: "r", keyId: "phk_x", secret: "y")
        XCTAssertNotNil(vm.revealedKey)
        vm.dismissReveal()
        XCTAssertNil(vm.revealedKey)
    }
}
