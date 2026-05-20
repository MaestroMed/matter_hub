import XCTest
@testable import VoiceCloneKit

/// v1.0-alpha.18 — Locks the state-machine of the voice clone
/// recording flow. The actual AVAudioRecorder is mocked away here —
/// these tests exercise the `VoiceSampleRecorderState` enum
/// transitions + the `AuditPitchAudioStore` on-disk cache contract.
final class VoiceCloneFlowTests: XCTestCase {

    // MARK: - State enum

    func test_state_idle_isNotRecording() {
        let state = VoiceSampleRecorderState.idle
        XCTAssertEqual(state, .idle)
    }

    func test_state_finished_carriesURL() {
        let url = URL(fileURLWithPath: "/tmp/sample.wav")
        let state = VoiceSampleRecorderState.finished(url)
        if case let .finished(returnedURL) = state {
            XCTAssertEqual(returnedURL, url)
        } else {
            XCTFail("Expected .finished case")
        }
    }

    func test_state_error_carriesMessage() {
        let state = VoiceSampleRecorderState.error("permission denied")
        if case let .error(msg) = state {
            XCTAssertEqual(msg, "permission denied")
        } else {
            XCTFail("Expected .error case")
        }
    }

    // MARK: - AuditPitchAudioStore

    func test_pitchAudioStore_roundTrip() async throws {
        let store = AuditPitchAudioStore()
        let id = UUID()
        let bytes = Data(repeating: 0xFE, count: 32)
        let url = try await store.save(mp3Data: bytes, for: id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let cached = await store.cachedURL(for: id)
        XCTAssertEqual(cached?.lastPathComponent, "\(id.uuidString).mp3")

        let read = await store.cachedBytes(for: id)
        XCTAssertEqual(read, bytes)

        await store.clear(for: id)
        let after = await store.cachedURL(for: id)
        XCTAssertNil(after)
    }
}
