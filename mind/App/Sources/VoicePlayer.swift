import Foundation
import AVFoundation
import MediaPlayer
import Combine
import GraphCore
import Observation

/// v0.18 — Voice read-back of any Node via `AVSpeechSynthesizer` with
/// the highest-quality Apple neural voice the system can offer (Siri
/// Natural at `.premium`, falling back to `.enhanced` then `.default`).
///
/// Concept
/// -------
/// The user opens any Node and taps "Listen" (speaker glyph). MIND
/// reads the title + content aloud through AirPods / the iPhone speaker
/// with full lock-screen + Control Center integration via
/// `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter`. Useful for
/// long audit reports while driving / running — Mehdi's original use
/// case.
///
/// Why `@MainActor @Observable`
/// ----------------------------
/// Every consumer (NodeDetailView, the mini playback bar) is SwiftUI.
/// `@Observable` macro generates the observation registrations so a
/// simple `@State private var voicePlayer = VoicePlayer.shared` in a
/// view triggers re-render on `isPlaying` / `progress` mutations. The
/// `@MainActor` annotation makes every mutation safe from concurrent
/// access — the `AVSpeechSynthesizerDelegate` callbacks (which Apple
/// dispatches on the main queue) hop back via `Task { @MainActor in }`
/// to keep the actor-isolation contract intact under Swift 6 strict
/// concurrency.
///
/// Threading model
/// ---------------
/// `AVSpeechSynthesizer` itself is *nonisolated* — it talks to the
/// underlying audio render thread directly. The delegate object is
/// kept as a private `nonisolated(unsafe)` companion (a tiny
/// `NSObject` shim) so the synthesizer can call into it from any
/// queue. The shim's only job is to forward delegate calls onto
/// `MainActor` via a captured `@MainActor` closure pointing back at
/// this player. That keeps the SwiftUI observation graph clean and
/// the audio thread unblocked.
///
/// Audio session
/// -------------
/// `.playback` + `.spokenAudio` is the documented combo for narration
/// apps that should keep playing on screen lock + over AirPods. We
/// pass `.mixWithOthers` so a Focus session's ambient track (when the
/// user is in a v0.50-era ambient mode) doesn't get killed by the
/// read-back.
///
/// Now-playing
/// -----------
/// On `play(...)` we populate `MPNowPlayingInfoCenter.default()
/// .nowPlayingInfo` with the Node title, "MIND" as artist, and the
/// estimated duration (text length divided by 200 chars/sec, the
/// published Siri Natural cadence). The elapsed time updates each
/// time the delegate fires `willSpeakRangeOfSpeechString`. Remote
/// command handlers wire lock-screen play / pause / toggle back into
/// this object so the AirPods double-tap also works.
@MainActor
@Observable
public final class VoicePlayer {

    // MARK: - Singleton

    /// Single instance is intentional — only one Node can be reading
    /// at a time and the audio session it owns is a global resource.
    /// Views grab `VoicePlayer.shared` rather than instantiating their
    /// own to avoid two players fighting for the same session.
    public static let shared = VoicePlayer()

    // MARK: - Observable state

    /// `true` while the synthesizer has an active utterance (including
    /// the brief moment a paused utterance is queued for resume). Views
    /// flip the Listen icon between `speaker.wave.2.fill` and
    /// `speaker.slash.fill` off this single source of truth.
    public private(set) var isPlaying: Bool = false

    /// The Node whose text is currently queued — `nil` when stopped.
    /// Used by NodeDetailView's Listen button to disambiguate "tapping
    /// listen on the open node" from "tapping listen while another
    /// node is reading" (which currently stops + restarts).
    public private(set) var currentNodeID: UUID?

    /// `[0.0, 1.0]` based on the latest character offset reported by
    /// `willSpeakRangeOfSpeechString`. Drives the mini playback bar's
    /// progress indicator. Resets to 0 on `stop()`.
    public private(set) var progress: Double = 0

    /// Voice identifier currently used (e.g.
    /// `com.apple.voice.premium.fr-FR.Audrey`). Surface for telemetry
    /// + Settings diagnostics — knowing whether the user landed on a
    /// premium voice or fell back to default is critical when
    /// debugging "audio sounds robotic".
    public private(set) var currentVoiceIdentifier: String?

    // MARK: - Internals (non-observable)

    /// `AVSpeechSynthesizer` is reused across calls to avoid the audio
    /// session re-activation cost of building a fresh one each tap.
    /// Marked `@ObservationIgnored` so Observable doesn't track its
    /// reference identity (it never changes after init).
    @ObservationIgnored
    private let synthesizer = AVSpeechSynthesizer()

    /// Delegate shim — see threading model above.
    @ObservationIgnored
    private let delegateShim: SynthesizerDelegate

    /// Total character count of the current utterance — denominator
    /// for the `progress` ratio. Cached because Apple's delegate
    /// callback gives us the offset but not the total.
    @ObservationIgnored
    private var currentTotalCharacters: Int = 0

    /// Estimated duration in seconds of the current utterance — feeds
    /// `MPMediaItemPropertyPlaybackDuration` so the lock-screen
    /// scrubber reflects a believable length. Computed from text size
    /// at play start; the elapsed-time field is updated incrementally
    /// from `progress`.
    @ObservationIgnored
    private var currentEstimatedDuration: TimeInterval = 0

    /// Wall-clock timestamp when the current utterance started — used
    /// to feed `MPNowPlayingInfoPropertyElapsedPlaybackTime`.
    @ObservationIgnored
    private var currentStartedAt: Date?

    // MARK: - Init

    private init() {
        self.delegateShim = SynthesizerDelegate()
        self.delegateShim.owner = self
        self.synthesizer.delegate = delegateShim
        registerRemoteCommands()
    }

    // MARK: - Public API

    /// Start reading `text` aloud, tagging the current playback with
    /// `nodeID`. If another utterance is already playing it's stopped
    /// first so the new one starts cleanly — only one Node can read
    /// at a time.
    ///
    /// Empty text is a no-op (with a telemetry breadcrumb so a UI
    /// regression that taps Listen on an empty Node still surfaces
    /// in Sentry).
    ///
    /// - Parameters:
    ///   - text: prose to speak. Markdown syntax (`**bold**`, `#`,
    ///     `[link](url)`) is passed through as-is — the synthesizer
    ///     reads it character-by-character, which is acceptable for
    ///     v0.18. A future pass can strip markdown via
    ///     `MarkdownRenderer.attributedString(from:).characters`.
    ///   - nodeID: caller's Node identifier, surfaced via
    ///     `currentNodeID` for view disambiguation.
    ///   - locale: BCP-47 language tag. Defaults to `fr-FR` because
    ///     Mehdi is the v0.18 user; the public TestFlight gets
    ///     `en-US` via locale auto-detect from `NSLocale.current`
    ///     in callers that don't pass an explicit value.
    public func play(
        text: String,
        nodeID: UUID,
        locale: String = "fr-FR"
    ) async {
        // Empty text → early return. The Listen button shouldn't even
        // be tappable on a Node with no body, but defensively bail so
        // the audio session isn't activated for nothing.
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            MINDTelemetry.warning(
                "voice.play.failed",
                data: ["reason": "empty.text", "nodeID": nodeID.uuidString]
            )
            return
        }

        // If something is already playing, stop it cleanly before
        // queuing the new utterance — avoids two voices overlapping
        // during the rapid tap-tap "Listen on A, then Listen on B"
        // race.
        if isPlaying {
            stop()
        }

        // Activate the audio session for spoken-audio playback. Failure
        // here is logged but not fatal — the synthesizer will still
        // try to play (it may succeed if another component already
        // activated the session, e.g. AirPods just disconnected).
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.mixWithOthers, .duckOthers]
            )
            try session.setActive(true, options: [])
        } catch {
            MINDTelemetry.warning(
                "voice.play.audioSession.failed",
                data: ["error": String(describing: error)]
            )
        }

        // Voice selection — pick the highest-quality voice for the
        // requested locale, with the documented fallback chain.
        let voice = Self.preferredVoice(forLocale: locale)
        currentVoiceIdentifier = voice?.identifier

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0
        utterance.postUtteranceDelay = 0

        currentNodeID = nodeID
        currentTotalCharacters = trimmed.count
        currentEstimatedDuration = Self.estimatedDuration(forCharacters: trimmed.count)
        currentStartedAt = .now
        progress = 0
        isPlaying = true

        publishNowPlayingInfo(title: trimmed.prefix(40).description, elapsed: 0)

        MINDTelemetry.info(
            "voice.play.started",
            data: [
                "nodeID": nodeID.uuidString,
                "characters": String(currentTotalCharacters),
                "voice": voice?.identifier ?? "system.default",
                "quality": Self.qualityName(voice?.quality),
                "locale": locale,
            ]
        )

        synthesizer.speak(utterance)
    }

    /// Pause an in-flight utterance at the next word boundary. No-op
    /// when nothing is playing. The audio session stays active so a
    /// `resume()` picks up instantly.
    public func pause() {
        guard isPlaying else { return }
        synthesizer.pauseSpeaking(at: .word)
        updateNowPlayingPlaybackRate(0)
    }

    /// Resume a paused utterance. No-op when the synthesizer isn't
    /// paused (so calling `resume()` after a `stop()` is harmless).
    public func resume() {
        guard synthesizer.isPaused else { return }
        synthesizer.continueSpeaking()
        updateNowPlayingPlaybackRate(1)
    }

    /// Cancel the current utterance and tear down the now-playing
    /// info. Safe to call when nothing is playing — the
    /// `stopSpeaking(at:)` call is itself a no-op in that case, and
    /// the state reset below idempotently lands the player in
    /// "stopped" state.
    public func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        clearPlaybackState()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        // Deactivate the audio session politely so other apps regain
        // priority (`notifyOthersOnDeactivation` lets the previously-
        // ducked app un-duck cleanly).
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: [.notifyOthersOnDeactivation]
        )
    }

    // MARK: - State reset

    /// Idempotent state reset. Called from `stop()` and from the
    /// delegate's `didFinish` / `didCancel` callbacks so the observable
    /// state lands in "stopped" exactly once per utterance regardless
    /// of who ended it.
    fileprivate func clearPlaybackState() {
        isPlaying = false
        currentNodeID = nil
        progress = 0
        currentTotalCharacters = 0
        currentEstimatedDuration = 0
        currentStartedAt = nil
    }

    /// Called by the delegate shim every time the synthesizer
    /// advances. Recomputes `progress` against the cached total and
    /// nudges the now-playing elapsed time so the lock-screen
    /// scrubber tracks the read.
    fileprivate func recordProgress(characterOffset: Int) {
        guard currentTotalCharacters > 0 else { return }
        let p = Double(characterOffset) / Double(currentTotalCharacters)
        progress = min(max(p, 0), 1)
        let elapsed = currentEstimatedDuration * progress
        updateNowPlayingElapsed(elapsed)
    }

    // MARK: - Now-playing

    private func publishNowPlayingInfo(title: String, elapsed: TimeInterval) {
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = title
        info[MPMediaItemPropertyArtist] = "MIND"
        info[MPMediaItemPropertyPlaybackDuration] = currentEstimatedDuration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        info[MPNowPlayingInfoPropertyPlaybackRate] = 1.0
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateNowPlayingElapsed(_ elapsed: TimeInterval) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateNowPlayingPlaybackRate(_ rate: Double) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyPlaybackRate] = rate
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - Remote commands

    /// Wires lock-screen + Control Center + AirPods double-tap into
    /// this object. Called once from `init`, idempotent (the framework
    /// dedupes by command identity, so even if init runs twice — which
    /// it can't because of `Self.shared`'s `let` — the second
    /// registration is a no-op).
    private func registerRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.removeTarget(nil)
        center.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.resume()
            return .success
        }

        center.pauseCommand.removeTarget(nil)
        center.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.pause()
            return .success
        }

        center.togglePlayPauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if self.synthesizer.isPaused {
                self.resume()
            } else if self.isPlaying {
                self.pause()
            }
            return .success
        }

        center.stopCommand.removeTarget(nil)
        center.stopCommand.addTarget { [weak self] _ in
            self?.stop()
            return .success
        }
    }

    // MARK: - Pure helpers (covered by VoicePlayerTests)

    /// Estimate utterance duration in seconds from character count.
    /// 200 chars/sec is roughly Siri Natural's published cadence on a
    /// neutral French sentence. Used only to populate the now-playing
    /// info's `playbackDuration` field; nothing else relies on the
    /// estimate being exact (and the real cadence varies with text
    /// content anyway).
    public static func estimatedDuration(forCharacters count: Int) -> TimeInterval {
        guard count > 0 else { return 0 }
        let charsPerSecond: Double = 200
        return Double(count) / charsPerSecond
    }

    /// Pick the highest-quality voice available for `locale`, falling
    /// back to a sibling-locale voice when the requested locale isn't
    /// installed, then to `nil` (system default) as a last resort.
    ///
    /// Priority chain (per ULTRAPLAN spec):
    /// 1. A `.premium` voice for `locale` (Siri Natural).
    /// 2. An `.enhanced` voice for `locale` (Siri Enhanced).
    /// 3. The first available `.default` voice for `locale`.
    /// 4. The same chain against `en-US` so the read still works on a
    ///    device that doesn't have FR voices installed (e.g. the
    ///    public-beta tester from EN-only iOS).
    /// 5. `nil` — `AVSpeechUtterance` picks the system default.
    public static func preferredVoice(forLocale locale: String) -> AVSpeechSynthesisVoice? {
        if let v = bestVoice(forExactLocale: locale) {
            return v
        }
        // Locale fallback. Try the language root (`fr` if `fr-CA`
        // was requested), then en-US as the universal floor.
        let language = String(locale.prefix(2))
        if language != locale, let v = bestVoice(forExactLocale: language) {
            return v
        }
        if locale != "en-US", let v = bestVoice(forExactLocale: "en-US") {
            return v
        }
        return nil
    }

    /// Helper that does one quality-priority scan for the exact locale
    /// string passed in. Public for tests; production goes through
    /// `preferredVoice(forLocale:)` above.
    public static func bestVoice(forExactLocale locale: String) -> AVSpeechSynthesisVoice? {
        let all = AVSpeechSynthesisVoice.speechVoices()
        let candidates = all.filter {
            $0.language.caseInsensitiveCompare(locale) == .orderedSame
                || $0.language.lowercased().hasPrefix(locale.lowercased() + "-")
        }
        guard !candidates.isEmpty else { return nil }
        if let premium = candidates.first(where: { $0.quality == .premium }) {
            return premium
        }
        if let enhanced = candidates.first(where: { $0.quality == .enhanced }) {
            return enhanced
        }
        return candidates.first
    }

    /// String label for telemetry — `AVSpeechSynthesisVoiceQuality` is
    /// an Int-backed enum so this gives the Sentry timeline a readable
    /// value instead of `0`/`1`/`2`.
    public static func qualityName(_ quality: AVSpeechSynthesisVoiceQuality?) -> String {
        guard let quality else { return "none" }
        switch quality {
        case .default:  return "default"
        case .enhanced: return "enhanced"
        case .premium:  return "premium"
        @unknown default: return "unknown"
        }
    }
}

// MARK: - Synthesizer delegate shim

/// NSObject shim that bridges `AVSpeechSynthesizerDelegate` (nonisolated,
/// invoked from the audio render thread) back onto MainActor. Strictly
/// internal — only `VoicePlayer.init` instantiates it, and it forwards
/// every callback to the `weak` owner so a leaked shim doesn't keep the
/// player alive.
///
/// Why `@unchecked Sendable`
/// -------------------------
/// `AVSpeechSynthesizer.delegate` is a nonisolated weak reference that
/// Apple invokes from a private serial queue. To satisfy Swift 6
/// strict concurrency we declare the shim Sendable and serialise every
/// access to its (only) mutable property by reading it once at delegate
/// entry and hopping straight onto MainActor — no further state lives
/// here. The `nonisolated(unsafe)` marker on `owner` documents the
/// contract: the field is set exactly once at init (before the
/// synthesizer is wired) and never mutated again.
private final class SynthesizerDelegate: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {

    /// Set by the owner immediately after construction. `weak` so the
    /// shim doesn't extend the player's lifetime past the singleton's
    /// natural app-lifetime ownership. Marked `nonisolated(unsafe)`
    /// because the only writer is `VoicePlayer.init` on the MainActor
    /// before any delegate call can fire — see class doc comment.
    nonisolated(unsafe) weak var owner: VoicePlayer?

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {
        // The state is already `isPlaying = true` from `play()`. No-op
        // here — kept as a stub so future tracing breadcrumbs have a
        // home without changing the public contract.
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        // Snapshot the weak owner ONCE, off-actor — the pointer itself
        // is fine to read here. Touching its actor-isolated state is
        // forbidden, so we hand the owner to the MainActor task and
        // let it read `currentNodeID` inside the right isolation
        // domain.
        let owner = self.owner
        Task { @MainActor in
            let nodeID = owner?.currentNodeID
            owner?.clearPlaybackState()
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            try? AVAudioSession.sharedInstance().setActive(
                false,
                options: [.notifyOthersOnDeactivation]
            )
            MINDTelemetry.info(
                "voice.play.completed",
                data: ["nodeID": nodeID?.uuidString ?? "unknown"]
            )
        }
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        let owner = self.owner
        Task { @MainActor in
            let nodeID = owner?.currentNodeID
            owner?.clearPlaybackState()
            MINDTelemetry.info(
                "voice.play.cancelled",
                data: ["nodeID": nodeID?.uuidString ?? "unknown"]
            )
        }
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        let owner = self.owner
        let offset = characterRange.location + characterRange.length
        Task { @MainActor in
            owner?.recordProgress(characterOffset: offset)
        }
    }
}
