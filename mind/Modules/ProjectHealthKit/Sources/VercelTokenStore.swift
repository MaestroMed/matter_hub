import Foundation
import Security

/// v1.0-alpha.8 — Keychain wrapper for the Vercel **personal access
/// token** that MIND uses to read deployment state per Project.
///
/// Why a personal token rather than OAuth?
/// ---------------------------------------
/// Same rationale as `NotionTokenStore` and `LinearTokenStore` — MIND
/// is solo-user. Mehdi creates a personal token once at
/// https://vercel.com/account/tokens, pastes it into MIND Settings →
/// "Intégrations dev", we ship. OAuth can land later if a public beta
/// tester needs it.
///
/// Service identifier is distinct from every other token store so
/// Vercel / GitHub / Notion / Linear stay isolated in the Keychain.
public enum VercelTokenStore {
    private static let service = "app.mind.ios.vercel"
    private static let account = "personal-token"

    public static func save(_ token: String) {
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    public static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
