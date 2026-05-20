import XCTest
@testable import VoiceCloneKit

/// v1.0-alpha.18 — Locks the Keychain round-trip for the ElevenLabs
/// API key store. Same shape and same skip-on-Simulator pattern as
/// `IntegrationTokenStoresTests` — the iOS Simulator's Keychain
/// doesn't honour `kSecAttrAccessibleAfterFirstUnlock` the way a
/// real device does, so the round-trip can flake on CI sims.
final class ElevenLabsTokenStoreTests: XCTestCase {

    private var isOnSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    override func setUp() {
        super.setUp()
        ElevenLabsTokenStore.clear()
    }

    override func tearDown() {
        ElevenLabsTokenStore.clear()
        super.tearDown()
    }

    func test_save_and_read_roundTrips() throws {
        try XCTSkipIf(isOnSimulator,
                      "Skipping Keychain round-trip on Simulator — the real device path is verified manually.")
        ElevenLabsTokenStore.save("sk_eleven_demo")
        XCTAssertEqual(ElevenLabsTokenStore.read(), "sk_eleven_demo")
    }

    func test_clear_returnsNil() throws {
        try XCTSkipIf(isOnSimulator, "Skipping Keychain round-trip on Simulator.")
        ElevenLabsTokenStore.save("sk_eleven_demo_2")
        ElevenLabsTokenStore.clear()
        XCTAssertNil(ElevenLabsTokenStore.read())
    }

    func test_save_overwritesPreviousToken() throws {
        try XCTSkipIf(isOnSimulator, "Skipping Keychain round-trip on Simulator.")
        ElevenLabsTokenStore.save("first")
        ElevenLabsTokenStore.save("second")
        XCTAssertEqual(ElevenLabsTokenStore.read(), "second")
    }

    func test_read_whenNeverSaved_returnsNil() throws {
        try XCTSkipIf(isOnSimulator, "Skipping Keychain round-trip on Simulator.")
        ElevenLabsTokenStore.clear()
        XCTAssertNil(ElevenLabsTokenStore.read())
    }

    func test_clear_isIdempotent() throws {
        try XCTSkipIf(isOnSimulator, "Skipping Keychain round-trip on Simulator.")
        ElevenLabsTokenStore.clear()
        ElevenLabsTokenStore.clear()
        XCTAssertNil(ElevenLabsTokenStore.read())
    }
}
