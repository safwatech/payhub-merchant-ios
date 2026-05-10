import Foundation
import Security
import Payhub

/// Persists the merchant bearer-token pair in the iOS Keychain.
///
/// One `kSecClassGenericPassword` item, service `ly.payhub.merchant`, account
/// `tokens`, accessibility `afterFirstUnlock` (so a background push refresh can
/// read it while the device is locked but has been unlocked once since boot).
/// The token pair is stored as JSON.
struct KeychainTokenStore {
    static let shared = KeychainTokenStore()

    private let service = "ly.payhub.merchant"
    private let account = "tokens"

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func save(_ pair: TokenPair) {
        guard let data = try? JSONEncoder().encode(pair) else { return }
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        // Upsert: try update first, fall back to add.
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attrs as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery.merge(attrs) { _, new in new }
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    func load() -> TokenPair? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(TokenPair.self, from: data)
    }

    func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
