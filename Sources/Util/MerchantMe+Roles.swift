import Foundation
import Payhub

/// Visibility helpers for the More-tab "Business" section. The server still
/// enforces every action via RBAC + the license layer — these only decide which
/// affordances to render.
extension MerchantMe {
    /// A parent-merchant login (not scoped to a single sub-shop). Parents see the
    /// organisation-profile screen (read-only unless `isParentOwner`); sub-users
    /// don't see the "Business" section at all.
    var isParent: Bool { subMerchant == nil }

    /// A parent-merchant *owner* — the only role allowed to edit the org profile
    /// and manage sub-merchants / sub-users. Uses `effectiveRole` so a license
    /// downgrade (which collapses the effective role) hides the affordances.
    var isParentOwner: Bool { isParent && effectiveRole.lowercased() == "owner" }

    /// Parent owner *and* the aggregator entitlement is live — gates the
    /// sub-merchant / sub-user management screens.
    var canManageSubs: Bool { isParentOwner && (entitlements?.aggregator ?? false) }
}
