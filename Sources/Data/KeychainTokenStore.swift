import Foundation
import LocalAuthentication
import Security
import Payhub

/// Persists the merchant bearer-token pair in the iOS Keychain.
///
/// **Two keychain items** since 0.4.0:
///   - Access token: a `kSecClassGenericPassword` item, service
///     `ly.payhub.merchant`, account `access-token`,
///     `kSecAttrAccessibleAfterFirstUnlock`. Short-lived (~30 min); the SDK
///     re-issues it via the refresh token whenever it 401s.
///   - Refresh token: delegated to `RefreshTokenVault`, which adds a biometric
///     access-control gate when `AppSettings.appLockEnabled` is on. See
///     `RefreshTokenVault.swift` for the rationale.
///
/// Previous releases stored the pair as a single JSON blob; rewinding to that
/// shape would mean rewrapping the access token whenever the lock toggled,
/// which would prompt for a biometric on every login. The split keeps the
/// expensive flag on the long-lived value only.
struct KeychainTokenStore {
    static let shared = KeychainTokenStore()

    private let service = "ly.payhub.merchant"
    private let accessAccount = "access-token"
    private let legacyTokensAccount = "tokens"
    private let vault: RefreshTokenVault

    init() {
        // Read the persisted lock flag directly from UserDefaults so this
        // initializer doesn't have to hop the `@MainActor` boundary (the
        // store itself is value-typed and used from `actor`-isolated SDK
        // callbacks). The key matches `AppSettings.Key.appLockEnabled`.
        self.vault = RefreshTokenVault(service: "ly.payhub.merchant",
                                         account: "refresh-token",
                                         isLockEnabled: { UserDefaults.standard.bool(forKey: "payhub.appLockEnabled") })
    }

    /// Initializer for tests / DI — injects an isLockEnabled closure directly.
    init(isLockEnabled: @escaping () -> Bool) {
        self.vault = RefreshTokenVault(isLockEnabled: isLockEnabled)
    }

    /// Hand the active `LAContext` to the underlying vault. Called from
    /// `LockManager.evaluate` after a successful unlock so the SDK's next
    /// refresh-retry doesn't pop a second prompt.
    func bind(authenticationContext context: LAContext?) {
        vault.bind(context: context)
    }

    func save(_ pair: TokenPair) {
        saveAccess(pair.accessToken)
        vault.write(pair.refreshToken)
    }

    func load() -> TokenPair? {
        if let pair = loadFromLegacyBlob() {
            // One-time migration: rewrite into the split shape so the legacy
            // blob is gone. The vault will pick up the lock-on flag if it's
            // already toggled.
            save(pair)
            clearLegacyBlob()
            return pair
        }
        guard let access = loadAccess(), let refresh = vault.read() else { return nil }
        return TokenPair(accessToken: access, refreshToken: refresh)
    }

    func clear() {
        SecItemDelete(accessQuery() as CFDictionary)
        vault.delete()
        clearLegacyBlob()
    }

    /// Re-wrap the refresh token after the user toggles app lock. Called by
    /// `LockManager.setEnabled(_:)`. Idempotent + no-op when nothing is stored.
    func rewrapRefreshToken() {
        vault.rewrap()
    }

    // MARK: - Access-token CRUD

    private func saveAccess(_ token: String) {
        guard let data = token.data(using: .utf8) else { return }
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let updateStatus = SecItemUpdate(accessQuery() as CFDictionary, attrs as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = accessQuery()
            addQuery.merge(attrs) { _, new in new }
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    private func loadAccess() -> String? {
        var query = accessQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func accessQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accessAccount,
        ]
    }

    // MARK: - One-time migration from the pre-0.4.0 single-blob shape

    private func legacyQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: legacyTokensAccount,
        ]
    }

    private func loadFromLegacyBlob() -> TokenPair? {
        var query = legacyQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(TokenPair.self, from: data)
    }

    private func clearLegacyBlob() {
        SecItemDelete(legacyQuery() as CFDictionary)
    }
}

