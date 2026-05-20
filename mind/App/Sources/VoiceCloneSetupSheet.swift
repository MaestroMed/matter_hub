import SwiftUI
import AVFoundation
import DesignSystem
import GraphCore
import Settings
import VoiceCloneKit

/// v1.0-alpha.18 — Voice clone setup sheet. Walks Mehdi through the
/// five steps required to make every audit's pitch playable in his
/// own voice:
///
///   1. Paste the ElevenLabs API key (Keychain).
///   2. Auto-detect whether a "Mehdi Nafaa" voice already exists.
///   3. Record a 60-180s WAV sample with live peak-level visualizer.
///   4. Upload the sample → ElevenLabs returns a `voice_id`.
///   5. Test the cloned voice by synthesizing a short FR sentence.
///
/// State persists across launches via `MINDPreferences.elevenLabsVoiceID`
/// + `elevenLabsVoiceName`, so re-opening the sheet on an already-
/// cloned account skips straight to step 5 (the test playback).
struct VoiceCloneSetupSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var prefs = MINDPreferences.shared
    @State private var apiKey: String = ""
    @State private var apiKeySaved: Bool = false
    @State private var tokenValid: Bool? = nil
    @State private var showAPIKey: Bool = false

    @State private var existingVoices: [ElevenLabsVoice] = []
    @State private var existingVoicesLoading: Bool = false
    @State private var existingMatchVoiceID: String?

    @State private var recorder = VoiceSampleRecorder.shared
    @State private var sampleURL: URL?
    @State private var sampleSizeBytes: Int = 0

    @State private var uploading: Bool = false
    @State private var uploadError: String?

    @State private var testText: String = String(
        localized: "voiceClone.test.placeholder",
        bundle: .main,
        comment: "Default sentence pre-filled into the voice test text editor"
    )
    @State private var testPlaying: Bool = false
    @State private var testError: String?
    @State private var audioPlayer: AVAudioPlayer?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                tokenSection
                if tokenValid == true {
                    existingVoicesSection
                    if existingMatchVoiceID == nil {
                        recorderSection
                        uploadSection
                    }
                    if !prefs.elevenLabsVoiceID.isEmpty {
                        testSection
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .background {
            LiquidBackground().ignoresSafeArea()
        }
        .onAppear(perform: onAppear)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("voiceClone.title", bundle: .main)
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                Text("voiceClone.subtitle", bundle: .main)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(LiquidPalette.iris)
            }
        }
    }

    private var tokenSection: some View {
        LiquidCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("voiceClone.step.token", bundle: .main)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(LiquidPalette.iris)
                    .tracking(0.8)
                Text("voiceClone.token.subtitle", bundle: .main)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)

                HStack {
                    Group {
                        if showAPIKey {
                            TextField("sk_…", text: $apiKey)
                        } else {
                            SecureField("sk_…", text: $apiKey)
                        }
                    }
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: apiKey) { _, _ in
                        apiKeySaved = false
                        tokenValid = nil
                    }
                    Button {
                        showAPIKey.toggle()
                    } label: {
                        Image(systemName: showAPIKey ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background {
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(LiquidGradient.glassStroke, lineWidth: 1)
                        }
                }

                HStack(spacing: 8) {
                    LiquidButton(
                        title: apiKeySaved
                            ? String(localized: "settings.button.saved", bundle: .main)
                            : String(localized: "settings.button.save", bundle: .main),
                        systemImage: apiKeySaved ? "checkmark" : "key.fill"
                    ) {
                        saveAPIKey()
                    }
                    .disabled(apiKey.isEmpty)

                    Button(String(localized: "settings.button.clear", bundle: .main)) {
                        ElevenLabsTokenStore.clear()
                        apiKey = ""
                        apiKeySaved = false
                        tokenValid = nil
                        existingVoices = []
                        existingMatchVoiceID = nil
                    }
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)

                    Spacer()
                    statusDot
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var statusDot: some View {
        if let valid = tokenValid {
            HStack(spacing: 6) {
                Circle()
                    .fill(valid ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                    .shadow(color: (valid ? Color.green : Color.red).opacity(0.5), radius: 4)
                Text(valid
                     ? String(localized: "voiceClone.token.status.ok", bundle: .main)
                     : String(localized: "voiceClone.token.status.fail", bundle: .main))
                    .font(.system(.caption2, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        } else {
            EmptyView()
        }
    }

    private var existingVoicesSection: some View {
        LiquidCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("voiceClone.step.voice", bundle: .main)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(LiquidPalette.iris)
                    .tracking(0.8)
                if let matchID = existingMatchVoiceID,
                   let match = existingVoices.first(where: { $0.id == matchID }) {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("voiceClone.voice.alreadyCloned", bundle: .main)
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            Text(match.name)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            existingMatchVoiceID = nil
                        } label: {
                            Text("voiceClone.voice.recloneCTA", bundle: .main)
                                .font(.system(.caption, design: .rounded, weight: .semibold))
                                .foregroundStyle(LiquidPalette.iris)
                        }
                    }
                } else if existingVoicesLoading {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.mini)
                        Text("voiceClone.voice.loading", bundle: .main)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("voiceClone.voice.noMatch", bundle: .main)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var recorderSection: some View {
        LiquidCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Text("voiceClone.step.sample", bundle: .main)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(LiquidPalette.iris)
                    .tracking(0.8)
                Text("voiceClone.sample.subtitle", bundle: .main)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)

                visualizer
                    .frame(height: 80)
                    .frame(maxWidth: .infinity)

                HStack {
                    Text(durationString)
                        .font(.system(.title3, design: .monospaced, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    if let url = sampleURL {
                        Text(byteString(url))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 10) {
                    if recorder.isRecording {
                        LiquidButton(
                            title: String(localized: "voiceClone.record.stop", bundle: .main),
                            systemImage: "stop.circle.fill",
                            haptic: .warning
                        ) {
                            Task { await stopRecording() }
                        }
                    } else {
                        LiquidButton(
                            title: String(localized: "voiceClone.record.start", bundle: .main),
                            systemImage: "mic.fill",
                            haptic: .select
                        ) {
                            Task { await startRecording() }
                        }
                    }

                    if sampleURL != nil && !recorder.isRecording {
                        Button {
                            recorder.deleteCurrentSample()
                            sampleURL = nil
                            sampleSizeBytes = 0
                        } label: {
                            Label(
                                String(localized: "voiceClone.record.delete", bundle: .main),
                                systemImage: "trash"
                            )
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var visualizer: some View {
        // 30 vertical bars whose height tracks the recorder peak level.
        // Each bar's offset modulates the level so the bars never all
        // move in unison — the visual feels "alive" even when the
        // input is steady.
        GeometryReader { geo in
            HStack(spacing: 4) {
                ForEach(0..<30, id: \.self) { i in
                    let phase = sin(Date.now.timeIntervalSinceReferenceDate * 6 + Double(i) * 0.4)
                    let amplitude = max(0.06, Double(recorder.peakLevel) * (0.55 + 0.45 * phase))
                    Capsule(style: .continuous)
                        .fill(LiquidGradient.aurora)
                        .frame(width: max(2, (geo.size.width - 4 * 29) / 30),
                               height: CGFloat(amplitude) * geo.size.height)
                        .opacity(recorder.isRecording ? 1.0 : 0.45)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .animation(.easeOut(duration: 0.08), value: recorder.peakLevel)
        }
    }

    private var uploadSection: some View {
        Group {
            if sampleURL != nil {
                LiquidCard(cornerRadius: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("voiceClone.step.upload", bundle: .main)
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(LiquidPalette.iris)
                            .tracking(0.8)
                        Text("voiceClone.upload.label", bundle: .main)
                            .font(.system(.subheadline, design: .rounded))
                        if let error = uploadError {
                            Text(error)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.red)
                        }
                        HStack {
                            if uploading {
                                ProgressView().controlSize(.small)
                                Text("voiceClone.upload.inflight", bundle: .main)
                                    .font(.system(.subheadline, design: .rounded))
                                    .foregroundStyle(.secondary)
                            } else {
                                LiquidButton(
                                    title: String(localized: "voiceClone.upload.button", bundle: .main),
                                    systemImage: "icloud.and.arrow.up.fill",
                                    haptic: .success
                                ) {
                                    Task { await runUpload() }
                                }
                            }
                            Spacer()
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                EmptyView()
            }
        }
    }

    private var testSection: some View {
        LiquidCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("voiceClone.step.test", bundle: .main)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(LiquidPalette.iris)
                    .tracking(0.8)
                Text("voiceClone.test.subtitle", bundle: .main)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)

                TextEditor(text: $testText)
                    .font(.system(.body, design: .rounded))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 70)
                    .padding(12)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(LiquidGradient.glassStroke, lineWidth: 1)
                            }
                    }

                if let testError {
                    Text(testError)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.red)
                }

                HStack {
                    if testPlaying {
                        ProgressView().controlSize(.small)
                        Text("voiceClone.test.playing", bundle: .main)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                    } else {
                        LiquidButton(
                            title: String(localized: "voiceClone.test.play", bundle: .main),
                            systemImage: "play.circle.fill",
                            haptic: .select
                        ) {
                            Task { await runTest() }
                        }
                        .disabled(testText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Spacer()
                    Image(systemName: "waveform")
                        .foregroundStyle(LiquidPalette.iris)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Actions

    private func onAppear() {
        if let stored = ElevenLabsTokenStore.read() {
            apiKey = stored
            apiKeySaved = true
            Task { await validateOnAppear() }
        }
    }

    private func validateOnAppear() async {
        let valid = await ElevenLabsClient.shared.validateToken()
        await MainActor.run {
            tokenValid = valid
            if valid {
                Task { await loadExistingVoices() }
            }
        }
    }

    private func saveAPIKey() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        ElevenLabsTokenStore.save(trimmed)
        apiKeySaved = true
        MINDTelemetry.info("voiceClone.token.saved", data: ["length": "\(trimmed.count)"])
        Task {
            let valid = await ElevenLabsClient.shared.validateToken()
            await MainActor.run {
                tokenValid = valid
                if valid {
                    LiquidHaptics.success()
                    Task { await loadExistingVoices() }
                } else {
                    LiquidHaptics.warning()
                }
            }
        }
    }

    private func loadExistingVoices() async {
        await MainActor.run { existingVoicesLoading = true }
        do {
            let voices = try await ElevenLabsClient.shared.listVoices()
            await MainActor.run {
                existingVoices = voices
                existingVoicesLoading = false
                let savedID = prefs.elevenLabsVoiceID
                if !savedID.isEmpty, voices.contains(where: { $0.id == savedID }) {
                    existingMatchVoiceID = savedID
                } else if let mehdi = voices.first(where: {
                    $0.name.localizedCaseInsensitiveContains("Mehdi")
                }) {
                    existingMatchVoiceID = mehdi.id
                    prefs.elevenLabsVoiceID = mehdi.id
                    prefs.elevenLabsVoiceName = mehdi.name
                }
            }
        } catch {
            await MainActor.run {
                existingVoicesLoading = false
                MINDTelemetry.warning("voiceClone.voice.list.failed", data: [
                    "error": String(describing: error)
                ])
            }
        }
    }

    private func startRecording() async {
        do {
            try await recorder.start()
            LiquidHaptics.select()
        } catch {
            uploadError = String(describing: error)
            LiquidHaptics.warning()
        }
    }

    private func stopRecording() async {
        if let url = await recorder.stop() {
            sampleURL = url
            sampleSizeBytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            LiquidHaptics.success()
            MINDTelemetry.info("voiceClone.sample.recorded", data: [
                "bytes": "\(sampleSizeBytes)",
                "duration": String(format: "%.1f", recorder.duration),
            ])
        }
    }

    private func runUpload() async {
        guard let url = sampleURL else { return }
        await MainActor.run { uploading = true; uploadError = nil }
        MINDTelemetry.info("voiceClone.upload.started", data: ["bytes": "\(sampleSizeBytes)"])
        do {
            let data = try Data(contentsOf: url)
            let voiceID = try await ElevenLabsClient.shared.cloneVoice(
                name: "Mehdi Nafaa",
                description: "MIND studio cockpit voice",
                sampleWAVData: data
            )
            await MainActor.run {
                prefs.elevenLabsVoiceID = voiceID
                prefs.elevenLabsVoiceName = "Mehdi Nafaa"
                uploading = false
                LiquidHaptics.success()
                MINDTelemetry.info("voiceClone.upload.completed", data: ["voiceID": voiceID])
                Task { await loadExistingVoices() }
            }
        } catch {
            await MainActor.run {
                uploading = false
                uploadError = String(describing: error)
                LiquidHaptics.error()
                MINDTelemetry.warning("voiceClone.upload.failed", data: [
                    "error": String(describing: error)
                ])
            }
        }
    }

    private func runTest() async {
        let voiceID = prefs.elevenLabsVoiceID
        guard !voiceID.isEmpty else { return }
        await MainActor.run { testPlaying = true; testError = nil }
        MINDTelemetry.info("voiceClone.synthesis.started", data: ["voiceID": voiceID])
        do {
            let bytes = try await ElevenLabsClient.shared.synthesize(
                voiceID: voiceID,
                text: testText
            )
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [])
            try AVAudioSession.sharedInstance().setActive(true, options: [])
            let player = try AVAudioPlayer(data: bytes)
            player.prepareToPlay()
            player.play()
            audioPlayer = player
            await MainActor.run {
                testPlaying = false
                MINDTelemetry.info("voiceClone.test.played", data: ["bytes": "\(bytes.count)"])
            }
        } catch {
            await MainActor.run {
                testPlaying = false
                testError = String(describing: error)
                MINDTelemetry.warning("voiceClone.synthesis.failed", data: [
                    "error": String(describing: error)
                ])
            }
        }
    }

    // MARK: - Formatters

    private var durationString: String {
        let total = Int(recorder.duration)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private func byteString(_ url: URL) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(sampleSizeBytes))
    }
}
