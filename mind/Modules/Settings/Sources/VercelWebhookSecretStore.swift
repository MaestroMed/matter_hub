import Foundation
import Security

/// v1.1.0 — Keychain wrapper for the HMAC-SHA1 secret the deployed
/// Cloudflare Worker uses to verify inbound `/v1/vercel-webhook`
/// POSTs from Vercel's webhook delivery system.
///
/// Mirrors `WebhookSecretStore` (the lead-webhook variant) byte-for-
/// byte except for the keychain service identifier — same Keychain
/// API surface, same `kSecAttrAccessibleAfterFirstUnlock` policy.
/// Per-installation, not per-project: a single MIND device pins one
/// Worker, every Vercel project signs with the same secret. The
/// secret never leaves the device once stored.
public enum VercelWebhookSecretStore {
    private static let service = "app.mind.ios.vercel.webhook"
    private static let account = "vercel-webhook-secret"

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

/// v1.1.0 — Persisted Worker base URL used to display the
/// `/v1/vercel-webhook` row in Settings without prompting Mehdi to
/// retype it twice (once for leads, once for Vercel). Stored in App
/// Group UserDefaults so other targets (the App's deep-link path) can
/// surface the same URL if they ever need to.
public enum WebhookWorkerBaseURLStore {
    private static let key = "mind.webhook.workerBaseURL"
    private static let appGroup = "group.app.mind.ios"

    private static func defaults() -> UserDefaults {
        UserDefaults(suiteName: appGroup) ?? UserDefaults.standard
    }

    public static func save(_ urlString: String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            defaults().removeObject(forKey: key)
        } else {
            defaults().set(trimmed, forKey: key)
        }
    }

    public static func read() -> String? {
        let stored = defaults().string(forKey: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let stored, !stored.isEmpty else { return nil }
        return stored
    }

    /// Convenience: returns the resolved `/v1/vercel-webhook` URL if
    /// the base URL is configured. Trims a trailing slash so the
    /// final URL never doubles up `//v1/...`.
    public static func vercelWebhookURL() -> String? {
        guard var base = read() else { return nil }
        while base.hasSuffix("/") { base.removeLast() }
        return "\(base)/v1/vercel-webhook"
    }
}
