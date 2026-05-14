import Foundation
import LocalAuthentication
import Security

/// Refresh-token-at-rest vault, with an OS-enforced biometric / passcode gate
/// when the app-lock toggle is on.
///
/// Two storage modes, decided per-write by `isLockEnabled()`:
///   - **lock on**: a Keychain item with
///     `kSecAttrAccessControl = [.userPresence, .biometryCurrentSet]` against
///     `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly`. The OS prompts on
///     read unless the supplied `LAContext` is still inside its evaluated-auth
///     window (we bind the lock-screen's context via `bind(context:)`, which
///     lets the SDK's first 401-refresh-retry within ~5s skip a second prompt).
///   - **lock off**: a Keychain item with
///     `kSecAttrAccessible = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
///     — readable by a backgrounded process so an unattended push-refresh
///     succeeds. Equivalent to the pre-0.4.0 storage shape, just isolated to
///     its own item so a future lock-on rewrap doesn't reshape the access-token
///     row.
///
/// `KeychainTokenStore` delegates refresh-token get/set to the vault; access
/// tokens stay on the cheap `afterFirstUnlock` path because they're
/// short-lived and re-issuable from a refresh.
///
/// Mirrors `apps/merchant-android/.../data/RefreshTokenVault.kt` 1:1 in
/// behaviour — different OS primitives, same security envelope.
final class RefreshTokenVault {
    private let isLockEnabled: () -> Bool
    private let service: String
    private let account: String
    /// Last successful biometric `LAContext` — handed to `SecItemCopyMatching`
    /// so a freshly-evaluated unlock can power a quick read without
    /// re-prompting.
    private var lastContext: LAContext?

    init(service: String = "ly.payhub.merchant",
         account: String = "refresh-token",
         isLockEnabled: @escaping () -> Bool) {
        self.service = service
        self.account = account
        self.isLockEnabled = isLockEnabled
    }

    /// Hand off the `LAContext` that just authenticated the user (LockManager
    /// passes its post-evaluate context here). The OS treats a `SecItem*` read
    /// against a still-fresh context as already-authenticated.
    func bind(context: LAContext?) { self.lastContext = context }

    // MARK: - CRUD

    func write(_ token: String) {
        delete()
        guard let data = token.data(using: .utf8) else { return }
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]
        if isLockEnabled() {
            var cfError: Unmanaged<CFError>?
            // `[.userPresence, .biometryCurrentSet]`:
            //  - userPresence ⇒ Face ID / Touch ID / passcode fallback.
            //  - biometryCurrentSet ⇒ enrolling a new biometric invalidates
            //    the access-control and the next read returns errSecAuthFailed,
            //    forcing a fresh login (no stale tokens after a thief enrols
            //    their own face).
            if let ac = SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
                [.userPresence, .biometryCurrentSet],
                &cfError) {
                query[kSecAttrAccessControl as String] = ac
            } else {
                // Couldn't build the access control (device with no
                // passcode) — fall through to the lock-off path. The
                // LockManager already gates the toggle on `canEnable`, so
                // this is a defence-in-depth fallback.
                query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            }
        } else {
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        }
        SecItemAdd(query as CFDictionary, nil)
    }

    func read() -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if let ctx = lastContext {
            query[kSecUseAuthenticationContext as String] = ctx
        }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        default:
            // errSecItemNotFound / errSecUserCanceled / errSecAuthFailed all
            // resolve to "no readable refresh token" — the caller treats nil
            // as "you need to sign in again".
            return nil
        }
    }

    func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Migration helper called by `LockManager.setEnabled(_:)`: with the
    /// caller's updated `isLockEnabled` semantics, re-read the current value
    /// and re-write it so the access-control flags match the new mode. A
    /// no-op when nothing is stored. Safe to call on either toggle edge.
    func rewrap() {
        guard let current = read() else { return }
        delete()
        write(current)
    }
}
