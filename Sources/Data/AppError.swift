import Foundation
import Payhub

/// A user-facing error. The repository maps `PayhubError` (and anything else)
/// down to one of these so views never see SDK internals.
struct AppError: Error, Identifiable {
    let id = UUID()
    let title: String
    let message: String
    /// Whether retrying the same action might succeed (network blips, 5xx).
    let isRetryable: Bool
    /// Whether this means the session is no longer valid (→ kick to login).
    let isAuthFailure: Bool
    /// PayHub `request_id`, if the server returned one — surface it in support copy.
    let requestId: String?

    init(title: String, message: String, isRetryable: Bool = false,
         isAuthFailure: Bool = false, requestId: String? = nil) {
        self.title = title
        self.message = message
        self.isRetryable = isRetryable
        self.isAuthFailure = isAuthFailure
        self.requestId = requestId
    }

    static func from(_ error: Error) -> AppError {
        if let app = error as? AppError { return app }
        guard let pe = error as? PayhubError else {
            return AppError(title: "Something went wrong", message: error.localizedDescription)
        }
        switch pe {
        case let .api(kind, code, status, message, _, requestId):
            switch kind {
            case .authentication:
                // A 401 on the password / MFA endpoints isn't a session expiry —
                // it's "wrong password" / "wrong code" / "code needed". Keep the
                // session (don't `isAuthFailure`), so the screen can show the
                // inline error (and the change-password screen reveals the TOTP
                // field on `mfa_required`).
                if Self.nonSessionAuthCodes.contains(code) {
                    return AppError(title: "Check your input",
                                    message: friendlyMessage(code, fallback: message),
                                    requestId: requestId)
                }
                return AppError(title: "Session expired",
                                message: "Please sign in again.",
                                isAuthFailure: true, requestId: requestId)
            case .permission:
                // License / entitlement 403s carry a useful server message
                // ("contact your vendor to upgrade") — surface it verbatim.
                let permFallback = code.hasPrefix("hub.license.") ? message : "Your role can't perform this action."
                return AppError(title: code.hasPrefix("hub.license.") ? "Upgrade required" : "Not allowed",
                                message: friendlyMessage(code, fallback: permFallback),
                                requestId: requestId)
            case .notFound:
                return AppError(title: "Not found",
                                message: friendlyMessage(code, fallback: "That item no longer exists."),
                                requestId: requestId)
            case .validation:
                return AppError(title: "Check your input",
                                message: friendlyMessage(code, fallback: message),
                                requestId: requestId)
            case .idempotencyConflict:
                return AppError(title: "Already in progress",
                                message: friendlyMessage(code, fallback: "This request was already submitted."),
                                requestId: requestId)
            case .rateLimited:
                return AppError(title: "Too many requests",
                                message: "Please wait a moment and try again.",
                                isRetryable: true, requestId: requestId)
            case .gateway:
                return AppError(title: "Payment provider error",
                                message: friendlyMessage(code, fallback: "The payment provider is having trouble. Try again shortly."),
                                isRetryable: true, requestId: requestId)
            case .server:
                return AppError(title: "Server error",
                                message: "PayHub had a problem (HTTP \(status)). Try again shortly.",
                                isRetryable: true, requestId: requestId)
            case .other:
                return AppError(title: "Request failed",
                                message: message, requestId: requestId)
            }
        case let .transport(kind, message):
            switch kind {
            case .timeout:
                return AppError(title: "Timed out",
                                message: "The request took too long. Check your connection and try again.",
                                isRetryable: true)
            case .connection:
                return AppError(title: "Can't reach PayHub",
                                message: "Check your internet connection and the server URL, then try again.",
                                isRetryable: true)
            case .decode:
                return AppError(title: "Unexpected response",
                                message: "PayHub returned something we couldn't read. \(message)")
            }
        case .webhookSignature:
            return AppError(title: "Signature error", message: "A signature check failed.")
        case let .invalidArgument(m):
            return AppError(title: "Invalid input", message: m)
        }
    }

    /// 401 codes that mean "your input was wrong", not "your session died".
    private static let nonSessionAuthCodes: Set<String> = [
        "hub.merchant.mfa_required",
        "hub.merchant.bad_mfa",
        "hub.merchant.bad_credentials",
    ]

    /// Whether a `PayhubError` carrying this code means the change-password
    /// screen should reveal its authenticator-code field.
    var requiresMFACode: Bool {
        message.lowercased().contains("authenticator code")
    }

    /// Map a handful of well-known PayHub error codes to plain English.
    private static func friendlyMessage(_ code: String, fallback: String) -> String {
        switch code {
        case "hub.sub_merchant.ref_too_long":
            return "The order reference is too long for the selected payment provider. Use a shorter one."
        case "hub.pay_link.quota_exceeded":
            return "You've reached your active pay-link limit. Cancel or wait for some to expire."
        case "hub.pay_link.not_active":
            return "This pay-link isn't active, so it can't be changed."
        case "hub.merchant_user.last_owner":
            return "You can't remove the last owner."
        case "hub.auth.invalid_credentials":
            return "Wrong merchant code, username, or password."
        case "hub.auth.locked":
            return "This account is temporarily locked after too many attempts. Try again later."
        case "hub.auth.mfa_required":
            return "Multi-factor authentication is required."
        case "hub.auth.invalid_code":
            return "That verification code wasn't right."
        case "hub.auth.invalid_token":
            return "This link is invalid or has expired. Ask for a new one."
        // --- account / MFA / org / sub-merchant management ---
        case "hub.merchant.mfa_required":
            return "Enter your authenticator code to confirm."
        case "hub.merchant.bad_mfa":
            return "That code didn't match."
        case "hub.merchant.bad_credentials":
            return "Password doesn't match."
        case "hub.merchant.mfa_missing":
            return "Enter your authenticator code to confirm."
        case "hub.merchant.mfa_already_enabled":
            return "Two-factor is already enabled on your account."
        case "hub.merchant.mfa_not_enrolled":
            return "Start by enabling two-factor first."
        case "hub.merchant.mfa_not_enabled":
            return "Two-factor isn't currently enabled."
        case "hub.merchant.last_sub_owner":
            return "That would leave the shop with no active owner."
        case "hub.merchant.self_modify_forbidden":
            return "You can't change your own role or status here."
        case "hub.merchant.invite_no_contact", "hub.merchant.no_contact":
            return "Add an email or mobile number so the invite can be delivered."
        case "hub.merchant.owner_no_mfa":
            return "Enable two-factor on your own account before clearing someone else's."
        case "hub.license.limit_exceeded", "hub.license.feature_unavailable":
            return fallback   // server message already says "contact your vendor to upgrade"
        default:
            return fallback
        }
    }
}
