import XCTest
@testable import PayHubMerchant

final class FormatTests: XCTestCase {

    func testFormatLYDMinorUnits() {
        // LYD has 3 decimal places (millidinars).
        XCTAssertEqual(Money.format(minor: 4_500, currency: "LYD"), "4.500 LYD")
        XCTAssertEqual(Money.format(minor: 0, currency: "LYD"), "0.000 LYD")
        XCTAssertEqual(Money.format(minor: 1_234_567, currency: "LYD"), "1,234.567 LYD")
    }

    func testFormatTwoDecimalCurrency() {
        XCTAssertEqual(Money.format(minor: 4_500, currency: "USD"), "45.00 USD")
        XCTAssertEqual(Money.format(minor: 99, currency: "EUR"), "0.99 EUR")
    }

    func testFormatZeroDecimalCurrency() {
        XCTAssertEqual(Money.format(minor: 4_500, currency: "JPY"), "4,500 JPY")
    }

    func testToMinorRoundTrip() {
        XCTAssertEqual(Money.toMinor(majorString: "4.5", currency: "LYD"), 4_500)
        XCTAssertEqual(Money.toMinor(majorString: "4.500", currency: "LYD"), 4_500)
        XCTAssertEqual(Money.toMinor(majorString: "12", currency: "LYD"), 12_000)
        XCTAssertEqual(Money.toMinor(majorString: "0", currency: "LYD"), 0)
        XCTAssertEqual(Money.toMinor(majorString: "1,234.567", currency: "LYD"), 1_234_567)
        XCTAssertEqual(Money.toMinor(majorString: "9.99", currency: "USD"), 999)
    }

    func testToMinorRejectsBadInput() {
        XCTAssertNil(Money.toMinor(majorString: "", currency: "LYD"))
        XCTAssertNil(Money.toMinor(majorString: "abc", currency: "LYD"))
        XCTAssertNil(Money.toMinor(majorString: "-5", currency: "LYD"))
    }

    func testDecimalPlaces() {
        XCTAssertEqual(Money.decimalPlaces(for: "lyd"), 3)
        XCTAssertEqual(Money.decimalPlaces(for: "USD"), 2)
        XCTAssertEqual(Money.decimalPlaces(for: "JPY"), 0)
    }

    func testPayLinkStatusParsing() {
        XCTAssertEqual(PayLinkStatus(rawString: "ACTIVE"), .active)
        XCTAssertEqual(PayLinkStatus(rawString: "paid"), .paid)
        XCTAssertEqual(PayLinkStatus(rawString: "weird-thing"), .unknown)
    }

    func testWriteRoleGate() {
        XCTAssertTrue(isWriteRole("owner"))
        XCTAssertTrue(isWriteRole("SUB_OPERATOR"))
        XCTAssertFalse(isWriteRole("viewer"))
        XCTAssertFalse(isWriteRole("sub_viewer"))
    }
}
