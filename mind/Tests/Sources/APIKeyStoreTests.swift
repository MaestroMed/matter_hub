import XCTest
@testable import Intelligence
@testable import VisualKit

/// Round-trip tests for the two Keychain wrappers that hold MIND's
/// live API credentials. These are security-critical — a bug that
/// e.g. accidentally returns a different service's key, or fails to
/// clear on demand, would leak credentials between callers.
///
/// Simulator caveat
/// ----------------
/// On the iOS Simulator without a signing identity, `SecItemAdd`
/// returns `errSecMissingEntitlement` silently (the wrappers ignore
/// the status code on purpose — they're best-effort writes meant to
/// degrade gracefully on a non-iCloud-signed-in device). Tests that
/// exercise persistence therefore can't assert on `read()` after a
/// `save()` on Simulator — they'd fail by environment, not by bug.
/// Each test that needs persistence skips itself when running on
/// Simulator and documents the constraint inline.
///
/// On a real device (or a CI runner with a provisioning profile that
/// grants Keychain access), all tests run and validate the full
/// round-trip. The TestFlight build will exercise this path.
final class APIKeyStoreTests: XCTestCase {

    /// True when the runtime is the iOS Simulator. Cached so the check
    /// is free to call per-test.
    private var isOnSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    override func setUp() {
        super.setUp()
        APIKeyStore.clear()
        OpenAIAPIKeyStore.clear()
    }

    override func tearDown() {
        APIKeyStore.clear()
        OpenAIAPIKeyStore.clear()
        super.tearDown()
    }

    // MARK: - Anthropic store

    /// Always runs — verifies the no-key path. Doesn't depend on writes
    /// persisting, just on `read()` returning nil when the slot is empty
    /// (which Simulator handles correctly).
    func test_APIKeyStore_readReturnsNil_whenNeverSaved() {
        XCTAssertNil(APIKeyStore.read())
    }

    /// Always runs — `clear()` on an empty Keychain must not throw or
    /// crash. Important regression check: a previous implementation
    /// asserted on `SecItemDelete` status which raised on missing items.
    func test_APIKeyStore_clearIsIdempotent_onEmptyKeychain() {
        APIKeyStore.clear()
        APIKeyStore.clear()
        XCTAssertNil(APIKeyStore.read())
    }

    func test_APIKeyStore_saveAndRead_roundTrips() throws {
        try XCTSkipIf(isOnSimulator,
                      "Simulator SecItemAdd silently fails without a signing identity")
        let key = "sk-ant-test-\(UUID().uuidString)"
        APIKeyStore.save(key)
        XCTAssertEqual(APIKeyStore.read(), key)
    }

    func test_APIKeyStore_saveOverwritesPreviousKey() throws {
        try XCTSkipIf(isOnSimulator, "Keychain writes require a signed runtime")
        APIKeyStore.save("sk-ant-first")
        APIKeyStore.save("sk-ant-second")
        XCTAssertEqual(APIKeyStore.read(), "sk-ant-second",
                       "Save must be insert-or-replace, not insert-only — otherwise rotating the key in Settings would silently fail")
    }

    func test_APIKeyStore_clearRemovesPersistedKey() throws {
        try XCTSkipIf(isOnSimulator, "Keychain writes require a signed runtime")
        APIKeyStore.save("sk-ant-some-key")
        APIKeyStore.clear()
        XCTAssertNil(APIKeyStore.read())
    }

    // MARK: - OpenAI store

    func test_OpenAIAPIKeyStore_readReturnsNil_whenNeverSaved() {
        XCTAssertNil(OpenAIAPIKeyStore.read())
    }

    func test_OpenAIAPIKeyStore_clearIsIdempotent_onEmptyKeychain() {
        OpenAIAPIKeyStore.clear()
        OpenAIAPIKeyStore.clear()
        XCTAssertNil(OpenAIAPIKeyStore.read())
    }

    func test_OpenAIAPIKeyStore_saveAndRead_roundTrips() throws {
        try XCTSkipIf(isOnSimulator, "Keychain writes require a signed runtime")
        let key = "sk-openai-test-\(UUID().uuidString)"
        OpenAIAPIKeyStore.save(key)
        XCTAssertEqual(OpenAIAPIKeyStore.read(), key)
    }

    func test_OpenAIAPIKeyStore_saveOverwritesPreviousKey() throws {
        try XCTSkipIf(isOnSimulator, "Keychain writes require a signed runtime")
        OpenAIAPIKeyStore.save("sk-openai-first")
        OpenAIAPIKeyStore.save("sk-openai-second")
        XCTAssertEqual(OpenAIAPIKeyStore.read(), "sk-openai-second")
    }

    func test_OpenAIAPIKeyStore_clearRemovesPersistedKey() throws {
        try XCTSkipIf(isOnSimulator, "Keychain writes require a signed runtime")
        OpenAIAPIKeyStore.save("sk-openai-some-key")
        OpenAIAPIKeyStore.clear()
        XCTAssertNil(OpenAIAPIKeyStore.read())
    }

    // MARK: - Cross-store isolation

    func test_storesAreIsolated_byService() throws {
        try XCTSkipIf(isOnSimulator, "Keychain writes require a signed runtime")
        APIKeyStore.save("sk-ant-only")
        OpenAIAPIKeyStore.save("sk-openai-only")

        XCTAssertEqual(APIKeyStore.read(), "sk-ant-only",
                       "Anthropic store must not return the OpenAI value")
        XCTAssertEqual(OpenAIAPIKeyStore.read(), "sk-openai-only",
                       "OpenAI store must not return the Anthropic value")
    }

    func test_clearingOneStoreDoesNotAffectTheOther() throws {
        try XCTSkipIf(isOnSimulator, "Keychain writes require a signed runtime")
        APIKeyStore.save("sk-ant-survives")
        OpenAIAPIKeyStore.save("sk-openai-deleted")

        OpenAIAPIKeyStore.clear()

        XCTAssertEqual(APIKeyStore.read(), "sk-ant-survives",
                       "Clearing OpenAI must leave Anthropic intact")
        XCTAssertNil(OpenAIAPIKeyStore.read())
    }

    // MARK: - Edge content

    func test_APIKeyStore_handlesLongKey() throws {
        try XCTSkipIf(isOnSimulator, "Keychain writes require a signed runtime")
        // Anthropic keys are ~100 chars; test 2 KB to defend against any
        // hidden length limit in the Keychain Generic Password class.
        let key = String(repeating: "x", count: 2048)
        APIKeyStore.save(key)
        XCTAssertEqual(APIKeyStore.read()?.count, 2048)
    }

    func test_APIKeyStore_handlesUnicodeKey() throws {
        try XCTSkipIf(isOnSimulator, "Keychain writes require a signed runtime")
        // Keychain stores raw Data, but we encode UTF-8 — confirm
        // round-trip survives multi-byte characters even though no real
        // API issues them.
        let key = "sk-ant-éüñ漢字🚀"
        APIKeyStore.save(key)
        XCTAssertEqual(APIKeyStore.read(), key)
    }
}
