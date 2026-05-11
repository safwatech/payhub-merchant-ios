import Foundation

/// A typed view over the pay-link `status` string the API returns.
enum PayLinkStatus: String, CaseIterable {
    case active
    case paid
    case expired
    case cancelled
    case refunded
    case unknown

    init(rawString: String) {
        self = PayLinkStatus(rawValue: rawString.lowercased()) ?? .unknown
    }

    var label: String {
        switch self {
        case .active:    return NSLocalizedString("payLink.status.active", value: "Active", comment: "")
        case .paid:      return NSLocalizedString("payLink.status.paid", value: "Paid", comment: "")
        case .expired:   return NSLocalizedString("payLink.status.expired", value: "Expired", comment: "")
        case .cancelled: return NSLocalizedString("payLink.status.cancelled", value: "Cancelled", comment: "")
        case .refunded:  return NSLocalizedString("payLink.status.refunded", value: "Refunded", comment: "")
        case .unknown:   return NSLocalizedString("payLink.status.unknown", value: "Unknown", comment: "")
        }
    }

    var systemImage: String {
        switch self {
        case .active:    return "link.circle.fill"
        case .paid:      return "checkmark.circle.fill"
        case .expired:   return "clock.badge.exclamationmark.fill"
        case .cancelled: return "xmark.circle.fill"
        case .refunded:  return "arrow.uturn.backward.circle.fill"
        case .unknown:   return "questionmark.circle.fill"
        }
    }
}

/// The filter buckets shown above the pay-links list.
enum PayLinkFilter: String, CaseIterable, Identifiable {
    case all
    case needsFollowup
    case active
    case paid
    case expired
    case cancelled

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:           return NSLocalizedString("payLink.filter.all", value: "All", comment: "")
        case .needsFollowup: return NSLocalizedString("payLink.filter.needsFollowup", value: "Needs follow-up", comment: "")
        case .active:        return NSLocalizedString("payLink.filter.active", value: "Active", comment: "")
        case .paid:          return NSLocalizedString("payLink.filter.paid", value: "Paid", comment: "")
        case .expired:       return NSLocalizedString("payLink.filter.expired", value: "Expired", comment: "")
        case .cancelled:     return NSLocalizedString("payLink.filter.cancelled", value: "Cancelled", comment: "")
        }
    }

    var systemImage: String {
        switch self {
        case .all:           return "tray.full"
        case .needsFollowup: return "bell.badge"
        case .active:        return "link.circle"
        case .paid:          return "checkmark.circle"
        case .expired:       return "clock.badge.exclamationmark"
        case .cancelled:     return "xmark.circle"
        }
    }

    /// (status, bucket) query args for `PayhubMerchantClient.payLinks.list(...)`.
    var query: (status: String?, bucket: String?) {
        switch self {
        case .all:           return (nil, nil)
        case .needsFollowup: return (nil, "needs_followup")
        case .active:        return ("active", nil)
        case .paid:          return ("paid", nil)
        case .expired:       return ("expired", nil)
        case .cancelled:     return ("cancelled", nil)
        }
    }
}
