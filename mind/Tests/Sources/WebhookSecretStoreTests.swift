import XCTest
@testable import Settings

/// v1.0-alpha.5 — Round-trip + isolation tests for the Keychain
/// wrapper that holds the lead-webhook HMAC shared secret.
///
/// Same Simulator caveat as `APIKeyStoreTests`: on Simulator without
/// a signing identity, `SecItemAdd` returns `errSecMissingEntitlement`
/// silently, so the persistence-dependent assertions short-circuit
/// via `XCTSkipIf`. The clear-on-empty path runs on every runtime so
/// at least one path always exercises the wrapper.
final class WebhookSecretStoreTests: XCTestCase {

    private var isOnSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    override func setUp() {
        super.setUp()
        WebhookSecretStore.clear()
    }

    override func tearDown() {
        WebhookSecretStore.clear()
        super.tearDown()
    }

    // MARK: - No-write paths (always run)

    /// Locks the no-key contract: a fresh keychain must return nil so
    /// the Settings view's "Saved ✓" state stays false on first launch.
    func test_read_returnsNil_whenNeverSaved() {
        XCTAssertNil(WebhookSecretStore.read())
    }

    /// `clear()` on an empty keychain must not throw or crash. Same
    /// regression check as the APIKeyStore wrapper — a previous
    /// implementation asserted on `SecItemDelete` status which raised
    /// on missing items.
    func test_clear_isIdempotent_onEmptyKeychain() {
        WebhookSecretStore.clear()
        WebhookSecretStore.clear()
        XCTAssertNil(WebhookSecretStore.read())
    }

    // MARK: - Persistence paths (device-only)

    func test_save_and_read_roundTrips() throws {
        try XCTSkipIf(isOnSimulator,
                      "Simulator SecItemAdd silently fails without a signing identity")
        let secret = "deadbeef" + String(repeating: "a", count: 56) // 64-char hex
        WebhookSecretStore.save(secret)
        XCTAssertEqual(WebhookSecretStore.read(), secret)
    }

    func test_save_overwritesPreviousSecret() throws {
        try XCTSkipIf(isOnSimulator, "Keychain writes require a signed runtime")
        WebhookSecretStore.save("first-secret")
        WebhookSecretStore.save("second-secret")
        XCTAssertEqual(WebhookSecretStore.read(), "second-secret",
                       "Save must be insert-or-replace, not insert-only — rotating the secret in Settings must not silently fail")
    }

    func test_clear_removesPersistedSecret() throws {
        try XCTSkipIf(isOnSimulator, "Keychain writes require a signed runtime")
        WebhookSecretStore.save("some-secret")
        WebhookSecretStore.clear()
        XCTAssertNil(WebhookSecretStore.read())
    }
}
