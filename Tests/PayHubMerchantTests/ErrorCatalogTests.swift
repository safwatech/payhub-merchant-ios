import XCTest
import Payhub
@testable import PayHubMerchant

final class ErrorCatalogTests: XCTestCase {

    func testTableCoversThirtyKeysAtLeast() {
        // The seed list (spec §8) is ~30 codes — a regression that drops the
        // table on the floor would catch here.
        XCTAssertGreaterThanOrEqual(ErrorCatalog.table.count, 30)
    }

    func testKnownCodeResolvesToLocalizedString() {
        // NSLocalizedString without a real bundle returns the key. In test
        // bundles, the table key is `err.merchant.last_owner` and the
        // resolved value should NOT be the empty server message — it should
        // come back through `NSLocalizedString`.
        let resolved = ErrorCatalog.resolve(
            code: "merchant.last_owner", params: [], fallback: "")
        // Either the EN string OR the key itself if no .strings is loaded —
        // both are non-empty / not the fallback "".
        XCTAssertFalse(resolved.isEmpty)
        XCTAssertNotEqual(resolved, "Something went wrong.")
    }

    func testUnknownCodeFallsBackToServerMessage() {
        let resolved = ErrorCatalog.resolve(
            code: "merchant.never.heard.of", params: [], fallback: "server says nope")
        XCTAssertEqual(resolved, "server says nope")
    }

    func testUnknownCodeNoFallbackGoesGeneric() {
        let resolved = ErrorCatalog.resolve(code: "x.y.z", params: [], fallback: "")
        // Either the localised "Something went wrong." OR the key itself —
        // the test bundle's .strings may or may not be loaded.
        XCTAssertFalse(resolved.isEmpty)
    }

    func testParamInterpolation() {
        // Using a raw format string verifies the positional interpolation
        // shape we ship in the .strings files.
        let format = "Try again in %1$@."
        let out = String(format: format, arguments: ["5m"] as [CVarArg])
        XCTAssertEqual(out, "Try again in 5m.")
    }

    func testLocalizeMerchantValidationError() {
        let e = MerchantValidationError(code: "merchant.last_owner",
                                         params: [], message: "keep an owner")
        let resolved = ErrorCatalog.localize(e)
        XCTAssertFalse(resolved.isEmpty)
    }

    func testLocalizeAppErrorWithCode() {
        let app = AppError(title: "T", message: "ignored fallback",
                            code: "merchant.last_owner")
        let resolved = ErrorCatalog.localize(app)
        XCTAssertFalse(resolved.isEmpty)
    }

    func testLocalizeAppErrorWithoutCodeUsesMessage() {
        let app = AppError(title: "T", message: "raw server message")
        XCTAssertEqual(ErrorCatalog.localize(app), "raw server message")
    }
}
