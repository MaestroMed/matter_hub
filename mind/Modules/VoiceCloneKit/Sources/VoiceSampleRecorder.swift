import Foundation
import Observation
#if canImport(AVFoundation)
import AVFoundation
#endif

/// State of the voice-clone recorder. Surfaces in the
/// `VoiceCloneSetupSheet` UI as a colored chip (idle → grey, recording
/// → red pulse, finished → iris with playback bar). Promoted to a
/// dedicated enum so tests can drive the state machine without having
/// to read AVAudioRecorder under the hood.
public enum VoiceSampleRecorderState: Sendable, Equatable {
    case idle
    case recording
    case finished(URL)
    case error(String)
}

/// `@MainActor @Observable` wrapper around `AVAudioRecorder` plus a
/// peak-decibel sampler so the SwiftUI surface can drive a 30-bar
/// visualizer at 24 Hz without poking AV directly.
///
/// Output format: 44.1 kHz mono PCM 16-bit WAV — ElevenLabs explicitly
/// accepts WAV / MP3 / FLAC / WebM / Ogg containers; WAV with PCM
/// 16-bit linear keeps the upload deterministic (no encoder variation
/// across iOS versions) and the file size manageable (~5 MB per
/// minute, well under any practical mobile upload budget).
///
/// File location: `Documents/voice-samples/<timestamp>.wav`. The
/// folder is created on demand. Old samples persist so Mehdi can
/// "re-cloner" without losing the original training audio.
@MainActor
@Observable
public final class VoiceSampleRecorder {
    public static let shared = VoiceSampleRecorder()

    public private(set) var state: VoiceSampleRecorderState = .idle

    /// Wall-clock duration of the in-flight recording, refreshed via
    /// the meter timer every 1/24 of a second so the UI can render a
    /// monospace `MM:SS` counter that doesn't visibly jitter.
    public private(set) var duration: TimeInterval = 0

    /// Peak normalized 0…1 envelope sampled from the recorder. The
    /// 30-bar visualizer reads this directly and animates each bar's
    /// height with a `.spring()` so the bars feel like they're moving
    /// with Mehdi's voice instead of cutting on/off.
    public private(set) var peakLevel: Float = 0

    /// `true` while the recorder is actively capturing audio. Drives
    /// the start/stop button label swap in `VoiceCloneSetupSheet`.
    public var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    /// URL of the most-recently-finished sample, or nil before the
    /// first recording lands. Helper used by the playback preview
    /// + the upload button.
    public var currentSampleURL: URL? {
        if case let .finished(url) = state { return url }
        return nil
    }

    #if canImport(AVFoundation)
    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var startedAt: Date?
    #endif

    public init() {}

    /// Configures the audio session, instantiates the recorder, and
    /// starts capture. Throws an `ElevenLabsClientError.audioFormat`
    /// or `VoiceSampleRecorderError.session` on failure — the UI
    /// surfaces both as the same "Impossible de démarrer
    /// l'enregistrement" toast since the user can't differentiate.
    public func start() async throws {
        #if canImport(AVFoundation)
        let folder = try Self.samplesFolderURL()
        let timestamp = ISO8601DateFormatter().string(from: .now)
            .replacingOccurrences(of: ":", with: "-")
        let url = folder.appendingPathComponent("\(timestamp).wav")

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true, options: [])

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 44_100.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.prepareToRecord(), recorder.record() else {
            throw VoiceSampleRecorderError.session
        }
        self.recorder = recorder
        self.startedAt = .now
        self.duration = 0
        self.peakLevel = 0
        self.state = .recording

        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 24.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sampleMeter()
            }
        }
        self.meterTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        #else
        throw VoiceSampleRecorderError.session
        #endif
    }

    /// Stops the recorder, deactivates the audio session, and returns
    /// the URL of the freshly-written .wav file. Caller is expected
    /// to either play it back via AVAudioPlayer, hand it to
    /// `ElevenLabsClient.cloneVoice`, or discard it via
    /// `deleteCurrentSample()`.
    @discardableResult
    public func stop() async -> URL? {
        #if canImport(AVFoundation)
        guard let recorder else { return nil }
        recorder.stop()
        meterTimer?.invalidate()
        meterTimer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        let url = recorder.url
        self.recorder = nil
        self.startedAt = nil
        self.peakLevel = 0
        self.state = .finished(url)
        return url
        #else
        return nil
        #endif
    }

    /// Discards the current sample file (and the on-disk WAV) so the
    /// user can re-record without leaving junk in Documents.
    public func deleteCurrentSample() {
        if case let .finished(url) = state {
            try? FileManager.default.removeItem(at: url)
        }
        state = .idle
        duration = 0
        peakLevel = 0
    }

    // MARK: - Private

    #if canImport(AVFoundation)
    private func sampleMeter() {
        guard let recorder, recorder.isRecording, let startedAt else { return }
        recorder.updateMeters()
        let avgDB = recorder.averagePower(forChannel: 0)
        // -160 dB = silence floor on iOS; map to 0…1 linearly.
        let clamped = max(-60.0, min(0.0, Double(avgDB)))
        let normalized = Float((clamped + 60.0) / 60.0)
        self.peakLevel = normalized
        self.duration = Date.now.timeIntervalSince(startedAt)
    }
    #endif

    /// Returns `Documents/voice-samples/`, creating it if missing.
    /// Made public-static so tests can hermeticize the path with a
    /// custom override; today the only caller is `start()` itself.
    public static func samplesFolderURL() throws -> URL {
        let docs = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let folder = docs.appendingPathComponent("voice-samples", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.createDirectory(
                at: folder,
                withIntermediateDirectories: true
            )
        }
        return folder
    }
}

/// Recorder-specific failure cases. Folded into the UI as a generic
/// "Impossible de démarrer l'enregistrement" toast; the test surface
/// uses the distinct cases to assert exact failure paths.
public enum VoiceSampleRecorderError: Error, Sendable, Equatable {
    case session
    case alreadyRecording
}
