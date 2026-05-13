import Foundation
import AVFoundation
import Speech

@MainActor
@Observable
public final class VoiceCapture {
    public private(set) var isRecording = false
    public private(set) var transcript: String = ""
    public private(set) var error: String?

    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    public init() {}

    public func start() async {
        guard !isRecording else { return }
        error = nil
        transcript = ""

        let authorized = await requestAuthorization()
        guard authorized else {
            error = "Speech recognition permission denied."
            return
        }

        do {
            try configureSession()
            try startRecognition()
            isRecording = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func stop() async {
        guard isRecording else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        request = nil
        task = nil
        isRecording = false
    }

    private func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func startRecognition() throws {
        guard let recognizer, recognizer.isAvailable else {
            throw NSError(domain: "VoiceCapture", code: -1, userInfo: [NSLocalizedDescriptionKey: "Recognizer unavailable"])
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(iOS 13.0, *) { request.requiresOnDeviceRecognition = true }
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        task = recognizer.recognitionTask(with: request) { [weak self] result, _ in
            guard let self else { return }
            if let result {
                Task { @MainActor in
                    self.transcript = result.bestTranscription.formattedString
                }
            }
        }
    }
}
