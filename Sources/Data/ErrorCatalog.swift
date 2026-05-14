import Foundation
import Payhub

/// Maps server error-envelope codes (e.g. `merchant.last_owner`) to localised
/// strings drawn from `Localizable.strings` in `en.lproj` + `ar.lproj`. Falls
/// back to the server's English `message` for any code not in the table, and
/// finally to a generic `err.generic` string when even that is blank.
///
/// The catalogue stays small on purpose — the seed list of ~30 high-traffic
/// codes is documented in
/// `docs/superpowers/specs/2026-05-14-d6-d7-sdk-1.2-and-app-followups-design.md` §8.
/// Extending it: add a row here AND a matching `err.*` entry in both
/// `en.lproj/Localizable.strings` and `ar.lproj/Localizable.strings`.
///
/// Mirrors the Android `ErrorCatalog.kt` 1:1 so the two apps surface the same
/// strings on the same codes; param interpolation uses `String(format:)` with
/// positional `%1$@` / `%2$@` markers in the resource strings.
enum ErrorCatalog {
    /// `code → Localizable.strings key`. Keys are scoped under `err.` to
    /// stay clear of UI keys.
    static let table: [String: String] = [
        "merchant.invalid_credentials": "err.merchant.invalid_credentials",
        "merchant.locked_out": "err.merchant.locked_out",
        "merchant.last_owner": "err.merchant.last_owner",
        "merchant.disabled": "err.merchant.disabled",
        "mfa_required": "err.mfa_required_envelope",
        "hub.merchant.mfa_required": "err.mfa_required_envelope",
        "mfa.invalid_code": "err.mfa.invalid_code",
        "mfa.already_enabled": "err.mfa.already_enabled",
        "password.too_weak": "err.password.too_weak",
        "password.reuse": "err.password.reuse",
        "password.current_wrong": "err.password.current_wrong",
        "auth.session_expired": "err.auth.session_expired",
        "auth.bearer_expired": "err.auth.bearer_expired",
        "pay_link.quota_exceeded": "err.pay_link.quota_exceeded",
        "pay_link.expired": "err.pay_link.expired",
        "pay_link.cancelled": "err.pay_link.cancelled",
        "pay_link.already_paid": "err.pay_link.already_paid",
        "pay_link.max_retries": "err.pay_link.max_retries",
        "sub_merchant.code_taken": "err.sub_merchant.code_taken",
        "sub_merchant.has_payments": "err.sub_merchant.has_payments",
        "sub_merchant.disabled": "err.sub_merchant.disabled",
        "sub_merchant.aggregator_required": "err.sub_merchant.aggregator_required",
        "sub_user.last_owner": "err.sub_user.last_owner",
        "sub_user.username_taken": "err.sub_user.username_taken",
        "device.platform_keys_missing": "err.device.platform_keys_missing",
        "device.token_too_long": "err.device.token_too_long",
        "api_key.label_taken": "err.api_key.label_taken",
        "api_key.revoked": "err.api_key.revoked",
        "invite.expired": "err.invite.expired",
        "invite.consumed": "err.invite.consumed",
        "rate_limited": "err.rate_limited",
    ]

    /// Resolve an `AppError` against the catalogue. The repository fills in
    /// `code` + `params` whenever the source was an SDK typed error (or a
    /// PayhubError carrying a recognised envelope code).
    static func localize(_ error: AppError) -> String {
        resolve(code: error.code, params: error.params, fallback: error.message)
    }

    /// Resolve a bare `MerchantValidationError`.
    static func localize(_ error: MerchantValidationError) -> String {
        resolve(code: error.code, params: error.params, fallback: error.message)
    }

    /// Resolve a `code` directly — the lowest-level entry point. Exposed for
    /// tests; production callers should prefer the typed overloads above so
    /// the catalogue stays aligned with `AppError.from`.
    static func resolve(code: String?, params: [String], fallback: String) -> String {
        let key = code.flatMap { table[$0] }
        guard let key else {
            if !fallback.isEmpty { return fallback }
            return NSLocalizedString("err.generic", value: "Something went wrong.", comment: "")
        }
        let format = NSLocalizedString(key, comment: "")
        guard !params.isEmpty else { return format }
        // `String(format:arguments:)` with `[CVarArg]` interpolates `%1$@`,
        // `%2$@`, etc. positionally. We stringify everything — the server's
        // params arrive as strings already.
        return String(format: format, arguments: params.map { $0 as CVarArg })
    }
}
