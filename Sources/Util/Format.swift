import Foundation

/// Money + currency formatting.
///
/// PayHub amounts cross the wire in **minor units**. For LYD that's millidinars
/// (1 LYD = 1000 — three decimal places), unlike most ISO-4217 currencies which
/// are two-decimal. We special-case LYD and fall back to two decimals otherwise.
enum Money {
    static func decimalPlaces(for currency: String) -> Int {
        switch currency.uppercased() {
        case "LYD", "BHD", "KWD", "OMR", "TND", "JOD": return 3
        case "JPY", "KRW": return 0
        default: return 2
        }
    }

    /// `4500` LYD → `"4.500 LYD"`.
    static func format(minor: Int64, currency: String) -> String {
        let places = decimalPlaces(for: currency)
        let divisor = pow(10.0, Double(places))
        let value = Double(minor) / divisor

        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.minimumFractionDigits = places
        nf.maximumFractionDigits = places
        nf.groupingSeparator = ","
        let number = nf.string(from: NSNumber(value: value)) ?? "\(value)"
        return "\(number) \(currency.uppercased())"
    }

    /// Convert a user-entered major-unit decimal string (e.g. "4.5") to minor units.
    /// Returns nil if the string isn't a valid non-negative amount.
    static func toMinor(majorString: String, currency: String) -> Int64? {
        let trimmed = majorString.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "")
        guard !trimmed.isEmpty, let value = Decimal(string: trimmed), value >= 0 else { return nil }
        let places = decimalPlaces(for: currency)
        var scaled = value
        var pow10 = Decimal(1)
        for _ in 0..<places { pow10 *= 10 }
        scaled *= pow10
        var rounded = Decimal()
        var copy = scaled
        NSDecimalRound(&rounded, &copy, 0, .plain)
        let ns = rounded as NSDecimalNumber
        return ns.int64Value
    }
}

/// ISO-8601 timestamp parsing — the API returns RFC 3339 strings, sometimes
/// with fractional seconds, sometimes without.
enum ISO {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func date(from string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        return withFraction.date(from: string) ?? plain.date(from: string)
    }
}

/// PSP display names — keep in sync with the web SPA's PSP labels.
enum PSP {
    /// The PSPs a pay-link can offer to a customer.
    static let all: [(code: String, label: String, symbol: String)] = [
        ("sadad", "Sadad", "creditcard"),
        ("moamalat", "Moamalat (Card)", "creditcard.fill"),
        ("mobicash", "Mobicash QR", "qrcode"),
        ("tlync", "T-Lync", "link"),
    ]

    static func label(_ code: String) -> String {
        all.first { $0.code == code.lowercased() }?.label ?? code.capitalized
    }
}
