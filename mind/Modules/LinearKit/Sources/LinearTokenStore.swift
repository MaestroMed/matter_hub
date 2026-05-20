import Foundation
import Security

/// Keychain wrapper for the Linear **personal API key** that MIND uses
/// to convert audit Quick Wins into issues via the Linear GraphQL API.
///
/// Why a personal API key rather than OAuth?
/// ------------------------------------------
/// MIND stays solo-user. Mehdi creates a key once at
/// https://linear.app/settings/api, copies it into MIND Settings →
/// "Linear sync". Linear's GraphQL endpoint accepts the personal API
/// key on every request via the `Authorization` header identically to
/// an OAuth-issued access token, so we skip the OAuth dance, client
/// ID/secret plumbing, and the callback URL. OAuth can land later if a
/// public beta tester ever needs it — the actor + builder split keeps
/// the swap surface tiny.
///
/// Same Keychain shape as `NotionTokenStore` (paste-token mirror) so
/// adding the third token in v0.13+ is a copy/paste of this file with
/// a new service id. The three sync surfaces stay isolated by service
/// (`app.mind.ios.notion`, `app.mind.ios.linear`, …) so revoking one
/// never touches the others.
public enum LinearTokenStore {
    private static let service = "app.mind.ios.linear"
    private static let account = "personal-api-key"

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
