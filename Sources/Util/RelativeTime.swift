import Foundation

/// Relative-time strings ("in 3 hours", "2 days ago").
enum RelativeTime {
    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    static func string(for date: Date, relativeTo reference: Date = Date()) -> String {
        formatter.localizedString(for: date, relativeTo: reference)
    }

    /// "Expires in 3 hours" / "Expired 1 day ago" / nil if no date.
    static func expiry(_ iso: String?, reference: Date = Date()) -> String? {
        guard let date = ISO.date(from: iso) else { return nil }
        let rel = string(for: date, relativeTo: reference)
        return date > reference ? "Expires \(rel)" : "Expired \(rel.replacingOccurrences(of: "in ", with: ""))"
    }

    /// Whether `iso` is within `hours` from `reference` and still in the future.
    static func isWithin(hours: Int, of iso: String?, reference: Date = Date()) -> Bool {
        guard let date = ISO.date(from: iso) else { return false }
        let delta = date.timeIntervalSince(reference)
        return delta > 0 && delta <= Double(hours) * 3600
    }
}
