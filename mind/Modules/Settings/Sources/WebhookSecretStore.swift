import Foundation
import Security

/// v1.0-alpha.5 — Keychain wrapper for the shared HMAC secret the
/// deployed Cloudflare Worker (`mind/tools/cloudflare-worker`) and
/// every connected client site use to sign / verify inbound
/// `/v1/leads` POSTs.
///
/// Why Keychain (not UserDefaults)
/// -------------------------------
/// The secret authenticates webhook traffic on Mehdi's behalf — a
/// leak lets an attacker forge inbound leads. Same threat shape as
/// the Anthropic / OpenAI / Notion / Linear tokens, same Keychain
/// shape for consistency. Service identifier distinct so the
/// providers stay isolated.
///
/// The secret is per-installation, not per-Project: a single MIND
/// device has one Worker pinned to it, all client sites use the
/// same secret to sign their POSTs. Per-Project secrets would
/// double the operator surface (one rotation per AZConstruction /
/// IEFCo / Sconnect) for no real security gain — the Worker's
/// HMAC verify is already gated by the same secret regardless of
/// `projectID`.
public enum WebhookSecretStore {
    private static let service = "app.mind.ios.webhook"
    private static let account = "lead-webhook-secret"

    public static func save(_ secret: String) {
        let data = Data(secret.utf8)
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
