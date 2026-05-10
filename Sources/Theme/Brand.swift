import SwiftUI

/// PayHub's visual identity, in one place.
///
/// Brand colour is a warm amber (≈ #FAB64B). The `accent` here is a code
/// fallback; the asset-catalog `AccentColor` (light/dark variants) is what the
/// system actually uses for tints — keep them in sync.
enum Brand {
    /// Primary amber — buttons, links, selected states.
    static let amber = Color("AccentColor")

    /// A slightly deeper amber for pressed/active fills where contrast matters.
    static let amberDeep = Color(red: 0.90, green: 0.62, blue: 0.18)

    /// Subtle amber wash for card backgrounds / highlights.
    static let amberSoft = Color(red: 0.98, green: 0.71, blue: 0.29).opacity(0.14)

    /// Neutral surface for cards on top of the grouped background.
    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)

    /// Status palette — used by `StatusBadge` and counter cards.
    static func statusColor(for status: PayLinkStatus) -> Color {
        switch status {
        case .active:    return .blue
        case .paid:      return .green
        case .expired:   return .orange
        case .cancelled: return .secondary
        case .refunded:  return .purple
        case .unknown:   return .secondary
        }
    }

    /// Role badge tint.
    static func roleColor(for role: String) -> Color {
        switch role.lowercased() {
        case "owner", "sub_owner":               return .indigo
        case "developer":                        return .teal
        case "operator", "sub_operator":         return .blue
        case "viewer", "sub_viewer":             return .secondary
        default:                                  return .secondary
        }
    }
}

/// Whether a role can perform write actions (mirrors the server's RBAC; the
/// server is still the source of truth — this only gates affordances).
func isWriteRole(_ effectiveRole: String) -> Bool {
    switch effectiveRole.lowercased() {
    case "owner", "developer", "sub_owner", "sub_operator":
        return true
    default:
        return false
    }
}

/// Human-readable role label.
func roleLabel(_ role: String) -> String {
    switch role.lowercased() {
    case "owner":         return "Owner"
    case "developer":     return "Developer"
    case "operator":      return "Operator"
    case "viewer":        return "Viewer"
    case "sub_owner":     return "Shop Owner"
    case "sub_operator":  return "Shop Operator"
    case "sub_viewer":    return "Shop Viewer"
    default:              return role.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
