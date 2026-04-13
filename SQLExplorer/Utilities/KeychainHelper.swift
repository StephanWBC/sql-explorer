import Foundation
import Security

/// Secure credential storage using macOS Keychain
struct KeychainHelper {
    private static let service = "com.sqlexplorer.app"

    static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        // Delete existing
        SecItemDelete(query as CFDictionary)

        // Add new
        var addQuery = query
        addQuery[kSecValueData as String] = data
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Manual connection passwords

    /// Generate a stable, unique Keychain key for a manual SQL Auth connection.
    /// Format: `manual-conn-<uuid>`. Persisted as `keychainRef` on the Group/Favorite row.
    static func newManualConnectionRef() -> String {
        "manual-conn-\(UUID().uuidString)"
    }

    static func savePassword(ref: String, password: String) {
        save(key: ref, value: password)
    }

    static func loadPassword(ref: String) -> String? {
        load(key: ref)
    }

    static func deletePassword(ref: String) {
        delete(key: ref)
    }
}
