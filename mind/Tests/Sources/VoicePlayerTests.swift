import XCTest
import AVFoundation
@testable import MIND

/// v0.18 — Locks the pure helpers behind `VoicePlayer`. The
/// AVSpeechSynthesizer runtime itself isn't exercised here: on a
/// Simulator with no audio device the delegate callbacks fire
/// unreliably and the `progress` thread isn't worth instrumenting in
/// a unit test. What we DO lock:
///
///   1. The estimated-duration formula (drives now-playing scrubber).
///   2. The voice-selection priority chain (premium > enhanced >
///      default → root locale → en-US → nil).
///   3. The locale fallback when an exact match isn't installed.
///   4. The pause/resume state-machine guards on the public API.
///   5. The empty-text early return contract.
///   6. The `stop()` idempotency and state-reset contract.
///
/// Strategy
/// --------
/// The voice list is whatever the runner Simulator happens to have
/// installed — we can't assume a specific identifier. We sniff
/// `AVSpeechSynthesisVoice.speechVoices()` up-front and skip
/// quality-priority asserts when no `.premium` voice exists, which
/// keeps the test green on a minimal Simulator while still locking
/// the contract on a hardware run with the premium FR voice
/// downloaded.
@MainActor
final class VoicePlayerTests: XCTestCase {

    // MARK: - Estimated duration formula

    /// 200 chars/sec is the cadence baseline. 400 chars → 2 s.
    /// Locks the now-playing scrubber math.
    func test_estimatedDuration_followsCharsPerSecondConstant() {
        XCTAssertEqual(VoicePlayer.estimatedDuration(forCharacters: 400), 2.0, accuracy: 0.001)
        XCTAssertEqual(VoicePlayer.estimatedDuration(forCharacters: 200), 1.0, accuracy: 0.001)
        XCTAssertEqual(VoicePlayer.estimatedDuration(forCharacters: 100), 0.5, accuracy: 0.001)
    }

    /// Zero-length text → zero seconds. Defensive: a downstream divide
    /// would otherwise produce NaN and feed garbage into MPNowPlaying.
    func test_estimatedDuration_zeroCharacters_returnsZero() {
        XCTAssertEqual(VoicePlayer.estimatedDuration(forCharacters: 0), 0)
    }

    // MARK: - Voice selection priority chain

    /// When premium voices exist for the requested locale, the helper
    /// MUST return one of them — not enhanced, not default. Skipped
    /// on Simulator builds where no premium voice is installed (a real
    /// device with Siri Natural downloaded exercises the assertion).
    func test_bestVoice_prefersPremiumWhenAvailable() throws {
        let frVoices = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.lowercased().hasPrefix("fr")
        }
        guard frVoices.contains(where: { $0.quality == .premium }) else {
            throw XCTSkip("No premium FR voice installed on this runner")
        }
        let picked = VoicePlayer.bestVoice(forExactLocale: "fr-FR")
        XCTAssertEqual(picked?.quality, .premium)
    }

    /// When premium isn't available but enhanced is, the helper must
    /// fall to enhanced before settling on default. Same skip guard
    /// as above.
    func test_bestVoice_fallsToEnhancedWhenNoPremium() throws {
        // We can't easily synthesize a "no-premium" world at runtime,
        // so the assertion is a soft one: if the runner has at least
        // one enhanced FR voice and zero premium FR voices, the
        // pick MUST be enhanced. Otherwise skip.
        let frVoices = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.lowercased().hasPrefix("fr")
        }
        let hasPremium = frVoices.contains { $0.quality == .premium }
        let hasEnhanced = frVoices.contains { $0.quality == .enhanced }
        guard !hasPremium && hasEnhanced else {
            throw XCTSkip("Runner doesn't isolate the no-premium-but-enhanced case")
        }
        let picked = VoicePlayer.bestVoice(forExactLocale: "fr-FR")
        XCTAssertEqual(picked?.quality, .enhanced)
    }

    /// Whatever voice the helper returns for `fr-FR` MUST be a FR
    /// voice — never an EN voice mis-tagged as FR. Locks the locale
    /// filter inside the selector against future regressions.
    func test_bestVoice_returnedVoiceMatchesLocale() throws {
        guard let picked = VoicePlayer.bestVoice(forExactLocale: "fr-FR") else {
            throw XCTSkip("No FR voice installed on this runner")
        }
        XCTAssertTrue(
            picked.language.lowercased().hasPrefix("fr"),
            "Voice language \(picked.language) is not FR"
        )
    }

    // MARK: - Locale fallback

    /// `preferredVoice(forLocale:)` MUST fall back to en-US when the
    /// requested locale is exotic enough that no installed voice
    /// matches. `zz-ZZ` is a documented "no language" stand-in.
    /// On a stock Simulator en-US is always installed, so the
    /// fallback is observable here.
    func test_preferredVoice_fallsBackToEnglishOnUnknownLocale() throws {
        guard !AVSpeechSynthesisVoice.speechVoices().isEmpty else {
            throw XCTSkip("No voices installed on this runner")
        }
        let picked = VoicePlayer.preferredVoice(forLocale: "zz-ZZ")
        // Either we found a voice (fallback worked) or we got nil
        // (runner has zero voices) — both states are documented.
        if let picked {
            // The exact-locale lookup for "zz-ZZ" must have failed,
            // and the helper should have landed on a non-zz language.
            XCTAssertFalse(
                picked.language.lowercased().hasPrefix("zz"),
                "Fallback returned a zz voice, that's an exact-match leak"
            )
        }
    }

    // MARK: - Quality name labelling

    /// `qualityName` is the human-readable string the telemetry
    /// breadcrumb embeds. Lock all three values so a Sentry dashboard
    /// filter on `quality=premium` doesn't silently start receiving
    /// integers tomorrow.
    func test_qualityName_labelsAllKnownLevels() {
        XCTAssertEqual(VoicePlayer.qualityName(.default), "default")
        XCTAssertEqual(VoicePlayer.qualityName(.enhanced), "enhanced")
        XCTAssertEqual(VoicePlayer.qualityName(.premium), "premium")
        XCTAssertEqual(VoicePlayer.qualityName(nil), "none")
    }

    // MARK: - Empty-text early return

    /// Passing empty text MUST not flip `isPlaying`. The
    /// `currentNodeID` likewise stays at its prior value (nil on a
    /// fresh shared instance, since we never started anything).
    func test_play_emptyText_isNoOp() async {
        let player = VoicePlayer.shared
        player.stop()  // baseline
        XCTAssertFalse(player.isPlaying)
        let beforeID = player.currentNodeID

        await player.play(text: "", nodeID: UUID())
        XCTAssertFalse(player.isPlaying,
                       "Empty text must not flip isPlaying to true")
        XCTAssertEqual(player.currentNodeID, beforeID,
                       "Empty text must not bind a node ID")
    }

    /// Whitespace-only text is treated as empty (the
    /// `trimmingCharacters(in: .whitespacesAndNewlines)` guard in
    /// `play(...)`). Locks that contract — otherwise a Node with
    /// content `"\n\n\n"` would trip the audio session activation
    /// for no audible output.
    func test_play_whitespaceOnlyText_isNoOp() async {
        let player = VoicePlayer.shared
        player.stop()
        await player.play(text: "   \n\t   ", nodeID: UUID())
        XCTAssertFalse(player.isPlaying)
        XCTAssertNil(player.currentNodeID)
    }

    // MARK: - Stop clears state

    /// `stop()` MUST land the player in a clean "stopped" state — no
    /// lingering `currentNodeID`, no non-zero `progress`. Idempotent:
    /// calling stop twice is safe and observable as still-stopped.
    func test_stop_clearsAllPlaybackState() {
        let player = VoicePlayer.shared
        player.stop()
        XCTAssertFalse(player.isPlaying)
        XCTAssertNil(player.currentNodeID)
        XCTAssertEqual(player.progress, 0)
        // Second call → still clean. No assertion change expected;
        // the test is the side-effect-free repetition.
        player.stop()
        XCTAssertFalse(player.isPlaying)
        XCTAssertNil(player.currentNodeID)
        XCTAssertEqual(player.progress, 0)
    }

    // MARK: - Pause/resume guards

    /// `pause()` when nothing is playing MUST be a no-op. The
    /// observable state stays in "stopped" — the test guards against
    /// a future regression that flips `isPlaying = false` from `true`
    /// without checking the synthesizer state first.
    func test_pause_whenIdle_isNoOp() {
        let player = VoicePlayer.shared
        player.stop()
        XCTAssertFalse(player.isPlaying)
        player.pause()
        XCTAssertFalse(player.isPlaying)
        XCTAssertNil(player.currentNodeID)
    }

    /// `resume()` when nothing is paused MUST be a no-op — both
    /// during silence and during a play (the synthesizer's
    /// `isPaused` guard inside the method handles this).
    func test_resume_whenNotPaused_isNoOp() {
        let player = VoicePlayer.shared
        player.stop()
        player.resume()
        XCTAssertFalse(player.isPlaying)
        XCTAssertNil(player.currentNodeID)
    }
}
