import Foundation
import Security

/// Keychain wrapper for the Notion **internal integration token** that
/// MIND uses to POST audit pages to a user-configured database.
///
/// Why an integration token rather than OAuth?
/// -------------------------------------------
/// MIND is solo-user. Mehdi creates a Notion internal integration once
/// at https://www.notion.so/my-integrations, copies its secret token,
/// pastes it into MIND Settings → "Notion sync". The Notion API accepts
/// the integration token on every `POST /v1/pages` call identically to
/// an OAuth-issued token, so we skip the entire OAuth round-trip,
/// client ID/secret management, and callback URL plumbing. OAuth can
/// land later as v0.11.1 if a public beta tester ever needs it.
///
/// Same Keychain shape as `OpenAIAPIKeyStore` (Modules/VisualKit/Sources)
/// and `APIKeyStore` (Modules/Intelligence/Sources) for consistency —
/// service identifier distinct so the three providers stay isolated.
public enum NotionTokenStore {
    private static let service = "app.mind.ios.notion"
    private static let account = "integration-token"

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
