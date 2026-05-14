import Foundation
import Payhub

/// Tiny adapters over SDK model types — single source of truth for the
/// "active vs. not" boolean the UI uses (the server's wire shape is the
/// `status` string, with `"active"` meaning healthy and anything else
/// (`"disabled"`, `"suspended"`, …) meaning inactive). Mirroring the Android
/// equivalents in `apps/merchant-android/.../data/SdkBridges.kt`.

extension SubMerchant {
    /// Convenience the UI binds to. The server's `status` enum is a string —
    /// any value other than `"active"` is treated as inactive (the only
    /// other values today are `"disabled"` and `"suspended"`).
    var isActive: Bool { status == "active" }
}

extension SubUser {
    /// As above for cashiers.
    var isActive: Bool { status == "active" }
}

/// PATCH-shape conveniences. The SDK ships these structs as plain Encodable
/// value types; the app's view models build them incrementally and call
/// `isEmpty` to skip a no-op PATCH.

extension OrgPatch {
    /// `true` when no field is set — saves a round trip on a clean form.
    var isEmpty: Bool {
        name == nil && type == nil && legalName == nil && taxNumber == nil
            && commercialRegisterNo == nil && billingEmail == nil && supportEmail == nil
            && phone == nil && website == nil && addressLine1 == nil && addressLine2 == nil
            && city == nil && country == nil && logoUrl == nil
    }
}

extension SubMerchantPatch {
    /// `true` when no field is set.
    var isEmpty: Bool { name == nil && status == nil && externalRef == nil }
}

extension SubUserPatch {
    /// `true` when no field is set.
    var isEmpty: Bool {
        role == nil && status == nil && fullName == nil && email == nil
            && mobile == nil && phone == nil
    }
}
