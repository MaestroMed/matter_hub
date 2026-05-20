import Foundation
import Security

/// Keychain wrapper for the ElevenLabs API key that MIND uses to
/// clone Mehdi's voice once and then synthesize per-audit pitch
/// audio in that voice on demand.
///
/// Why a personal API key rather than OAuth?
/// -----------------------------------------
/// MIND is solo-user. Mehdi creates an ElevenLabs account once at
/// https://elevenlabs.io, copies the API key from Profile → API Key,
/// pastes it into MIND Settings → "Voice Clone". The ElevenLabs API
/// accepts the personal key on every `xi-api-key` header identically
/// to an OAuth-issued token, so we skip the entire OAuth round-trip,
/// client ID/secret management, and callback URL plumbing.
///
/// Same Keychain shape as `NotionTokenStore` (Modules/NotionKit) and
/// `LinearTokenStore` (Modules/LinearKit) for consistency — service
/// identifier distinct so the three providers stay isolated.
public enum ElevenLabsTokenStore {
    private static let service = "app.mind.ios.elevenlabs"
    private static let account = "api-key"

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
