import XCTest
@testable import VoiceCloneKit

/// v1.0-alpha.18 — Locks the pure helpers of the `ElevenLabsClient`
/// actor — multipart body byte shape, synthesis payload JSON shape,
/// `ElevenLabsVoice` JSON decoding. The HTTP round-trip is exercised
/// end-to-end via the simulator screenshot + the Settings → Voice
/// clone → Test flow on device. Everything below is pure — no
/// URLSession, no Keychain, no AVFoundation.
final class ElevenLabsClientTests: XCTestCase {

    // MARK: - Multipart body builder
    //
    // The body Data interleaves UTF-8 boundary delimiters with raw
    // binary sample bytes (a real WAV would carry every byte 0…255).
    // `String(data:encoding:.utf8)` fails on the binary slice, so the
    // tests decode the multipart frame bytewise via a Data-range
    // contains helper rather than trying to round-trip through String.

    private func contains(_ body: Data, _ needle: String) -> Bool {
        body.range(of: Data(needle.utf8)) != nil
    }

    func test_buildCloneMultipartBody_includesNameField() {
        let body = ElevenLabsClient.buildCloneMultipartBody(
            boundary: "TEST",
            name: "Mehdi Nafaa",
            description: "MIND studio cockpit voice",
            sampleWAVData: Data(repeating: 0xAA, count: 16)
        )
        XCTAssertTrue(contains(body, "--TEST\r\n"))
        XCTAssertTrue(contains(body, "Content-Disposition: form-data; name=\"name\""))
        XCTAssertTrue(contains(body, "Mehdi Nafaa"))
    }

    func test_buildCloneMultipartBody_includesDescriptionField() {
        let body = ElevenLabsClient.buildCloneMultipartBody(
            boundary: "B-42",
            name: "x",
            description: "MIND studio cockpit voice",
            sampleWAVData: Data(repeating: 0xAA, count: 16)
        )
        XCTAssertTrue(contains(body, "MIND studio cockpit voice"))
        XCTAssertTrue(contains(body, "Content-Disposition: form-data; name=\"description\""))
    }

    func test_buildCloneMultipartBody_includesFileField() {
        let body = ElevenLabsClient.buildCloneMultipartBody(
            boundary: "B-X",
            name: "n",
            description: "d",
            sampleWAVData: Data([0x52, 0x49, 0x46, 0x46]) // "RIFF" header bytes
        )
        XCTAssertTrue(contains(body, "filename=\"sample.wav\""))
        XCTAssertTrue(contains(body, "Content-Type: audio/wav"))
    }

    func test_buildCloneMultipartBody_endsWithClosingBoundary() {
        let body = ElevenLabsClient.buildCloneMultipartBody(
            boundary: "END-CHECK",
            name: "n",
            description: "d",
            sampleWAVData: Data(repeating: 0x00, count: 4)
        )
        // Suffix check: last 17 bytes must be "--END-CHECK--\r\n" (15 bytes after the boundary).
        let suffix = "--END-CHECK--\r\n"
        let suffixData = Data(suffix.utf8)
        XCTAssertEqual(body.suffix(suffixData.count), suffixData)
    }

    // MARK: - Synthesis payload

    func test_buildSynthesisPayload_pinsModelID() {
        let payload = ElevenLabsClient.buildSynthesisPayload(
            text: "Bonjour",
            modelID: "eleven_multilingual_v2"
        )
        XCTAssertEqual(payload["model_id"] as? String, "eleven_multilingual_v2")
    }

    func test_buildSynthesisPayload_preservesText() {
        let payload = ElevenLabsClient.buildSynthesisPayload(
            text: "Bonjour, c'est Mehdi.",
            modelID: "eleven_multilingual_v2"
        )
        XCTAssertEqual(payload["text"] as? String, "Bonjour, c'est Mehdi.")
    }

    func test_buildSynthesisPayload_includesVoiceSettings() {
        let payload = ElevenLabsClient.buildSynthesisPayload(
            text: "x",
            modelID: ElevenLabsClient.defaultModelID
        )
        let settings = payload["voice_settings"] as? [String: Any]
        XCTAssertNotNil(settings)
        XCTAssertEqual(settings?["use_speaker_boost"] as? Bool, true)
    }

    // MARK: - Voices decoding

    func test_decodeVoices_parsesEnvelope() throws {
        let json = #"""
        {
          "voices": [
            { "voice_id": "id-1", "name": "Mehdi Nafaa", "category": "cloned",
              "preview_url": "https://e.test/preview.mp3" },
            { "voice_id": "id-2", "name": "Rachel", "category": "premade" }
          ]
        }
        """#
        let data = Data(json.utf8)
        let voices = try ElevenLabsClient.decodeVoices(from: data)
        XCTAssertEqual(voices.count, 2)
        XCTAssertEqual(voices[0].id, "id-1")
        XCTAssertEqual(voices[0].name, "Mehdi Nafaa")
        XCTAssertEqual(voices[0].category, "cloned")
        XCTAssertEqual(voices[0].previewURL, "https://e.test/preview.mp3")
        XCTAssertEqual(voices[1].category, "premade")
        XCTAssertNil(voices[1].previewURL)
    }

    func test_decodeVoices_emptyArrayReturnsEmpty() throws {
        let json = "{ \"voices\": [] }"
        let voices = try ElevenLabsClient.decodeVoices(from: Data(json.utf8))
        XCTAssertEqual(voices.count, 0)
    }

    func test_decodeVoices_malformedJSON_throwsDecoding() {
        let bad = Data("not json".utf8)
        XCTAssertThrowsError(try ElevenLabsClient.decodeVoices(from: bad)) { error in
            guard case ElevenLabsClientError.decoding = error else {
                return XCTFail("Expected .decoding, got \(error)")
            }
        }
    }
}
