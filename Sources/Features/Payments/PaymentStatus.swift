import Foundation
import SwiftUI

/// A typed view over the payment `status` string the API returns. Powers the
/// payments-list status pill + filter chips.
enum PaymentStatus: String, CaseIterable {
    case pending
    case requiresAction = "requires_action"
    case succeeded
    case failed
    case cancelled
    case refunded
    case unknown

    init(rawString: String) {
        self = PaymentStatus(rawValue: rawString.lowercased()) ?? .unknown
    }

    var label: String {
        switch self {
        case .pending: return NSLocalizedString("payment.status.pending", value: "Pending", comment: "")
        case .requiresAction: return NSLocalizedString("payment.status.requiresAction", value: "Awaiting", comment: "")
        case .succeeded: return NSLocalizedString("payment.status.succeeded", value: "Paid", comment: "")
        case .failed: return NSLocalizedString("payment.status.failed", value: "Failed", comment: "")
        case .cancelled: return NSLocalizedString("payment.status.cancelled", value: "Cancelled", comment: "")
        case .refunded: return NSLocalizedString("payment.status.refunded", value: "Refunded", comment: "")
        case .unknown: return NSLocalizedString("payment.status.unknown", value: "Unknown", comment: "")
        }
    }

    var systemImage: String {
        switch self {
        case .pending, .requiresAction: return "clock.fill"
        case .succeeded: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        case .cancelled: return "xmark.circle.fill"
        case .refunded: return "arrow.uturn.backward.circle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .succeeded, .refunded: return .green
        case .failed, .cancelled: return .red
        case .pending, .requiresAction: return .orange
        case .unknown: return .secondary
        }
    }
}

/// Filter chips on the payments list. `wire` is the value sent to the server
/// (mapping to its `PaymentStatus` enum) — `nil` means "any".
enum PaymentStatusFilter: String, CaseIterable, Identifiable {
    case all
    case pending
    case requiresAction = "requires_action"
    case succeeded
    case failed
    case cancelled
    case refunded

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return NSLocalizedString("payment.filter.all", value: "All", comment: "")
        case .pending: return NSLocalizedString("payment.filter.pending", value: "Pending", comment: "")
        case .requiresAction: return NSLocalizedString("payment.filter.requiresAction", value: "Awaiting", comment: "")
        case .succeeded: return NSLocalizedString("payment.filter.succeeded", value: "Paid", comment: "")
        case .failed: return NSLocalizedString("payment.filter.failed", value: "Failed", comment: "")
        case .cancelled: return NSLocalizedString("payment.filter.cancelled", value: "Cancelled", comment: "")
        case .refunded: return NSLocalizedString("payment.filter.refunded", value: "Refunded", comment: "")
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "tray.full"
        case .pending: return "clock"
        case .requiresAction: return "hourglass"
        case .succeeded: return "checkmark.seal"
        case .failed: return "xmark.octagon"
        case .cancelled: return "xmark.circle"
        case .refunded: return "arrow.uturn.backward.circle"
        }
    }

    var wire: String? {
        switch self {
        case .all: return nil
        case .pending: return "pending"
        case .requiresAction: return "requires_action"
        case .succeeded: return "succeeded"
        case .failed: return "failed"
        case .cancelled: return "cancelled"
        case .refunded: return "refunded"
        }
    }
}
