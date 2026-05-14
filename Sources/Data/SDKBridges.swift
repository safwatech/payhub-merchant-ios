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
