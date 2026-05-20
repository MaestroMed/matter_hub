import XCTest
@testable import ProjectHealthKit

/// v1.0-alpha.8 — Locks the Keychain round-trip for the two new
/// dev-integration token stores. Same shape and same skip-on-Simulator
/// pattern as `APIKeyStoreTests` and `OpenAIAPIKeyStoreTests` — the
/// iOS Simulator's Keychain doesn't honour `kSecAttrAccessibleAfterFirstUnlock`
/// the way a real device does, so the round-trip can flake on CI sims.
final class IntegrationTokenStoresTests: XCTestCase {

    /// True when the test runs on the iOS Simulator. The Simulator
    /// keychain has been historically flaky on `SecItemAdd` /
    /// `SecItemCopyMatching` against the `kSecClassGenericPassword`
    /// surface (returns `errSecMissingEntitlement` in some Xcode
    /// versions), so we skip there — the round-trip is exercised on
    /// device + against the production Keychain on TestFlight builds.
    private var isOnSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    override func setUp() {
        super.setUp()
        VercelTokenStore.clear()
        GitHubTokenStore.clear()
    }

    override func tearDown() {
        VercelTokenStore.clear()
        GitHubTokenStore.clear()
        super.tearDown()
    }

    func test_vercelTokenStore_saveAndRead_roundTrips() throws {
        try XCTSkipIf(isOnSimulator,
                      "Skipping Keychain round-trip on Simulator — the real device path is verified manually.")

        VercelTokenStore.save("vercel_pat_token_abc")
        XCTAssertEqual(VercelTokenStore.read(), "vercel_pat_token_abc")
    }

    func test_vercelTokenStore_clear_returnsNil() throws {
        try XCTSkipIf(isOnSimulator,
                      "Skipping Keychain round-trip on Simulator.")

        VercelTokenStore.save("v_token")
        VercelTokenStore.clear()
        XCTAssertNil(VercelTokenStore.read())
    }

    func test_gitHubTokenStore_saveAndRead_roundTrips() throws {
        try XCTSkipIf(isOnSimulator,
                      "Skipping Keychain round-trip on Simulator.")

        GitHubTokenStore.save("ghp_token_abc")
        XCTAssertEqual(GitHubTokenStore.read(), "ghp_token_abc")
    }

    func test_gitHubTokenStore_clear_returnsNil() throws {
        try XCTSkipIf(isOnSimulator,
                      "Skipping Keychain round-trip on Simulator.")

        GitHubTokenStore.save("g_token")
        GitHubTokenStore.clear()
        XCTAssertNil(GitHubTokenStore.read())
    }
}
