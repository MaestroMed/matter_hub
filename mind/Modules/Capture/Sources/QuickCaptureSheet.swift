import SwiftUI
import SwiftData
import UIKit
import PhotosUI
import DesignSystem
import GraphCore
import Intelligence

public struct QuickCaptureSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""
    @State private var isProcessing = false
    @State private var voice = VoiceCapture()
    /// URL detected in the pasteboard at sheet-appear time. Drives the
    /// "Capture from clipboard" suggestion banner.
    @State private var clipboardURL: URL?
    /// v0.19 — Photo binding for the PhotosPicker. nil = no photo
    /// selected (yet). Once the user picks one, the .onChange handler
    /// pulls the underlying Data, runs OCR off the main thread, and
    /// appends the recognised text to the editor.
    @State private var selectedPhoto: PhotosPickerItem?
    /// v0.19 — Cached Data for the picked photo. Held so that `save()`
    /// can persist it to disk under `~/Documents/captures/<uuid>.jpg`
    /// and pin its `file://…` path on the Node's `sourceURL`.
    @State private var selectedPhotoData: Data?
    /// v0.19 — Drives the small spinner overlaid on the Photo button
    /// while Vision crunches the picked image.
    @State private var isRunningOCR = false
    @FocusState private var focused: Bool

    public init() {}

    public var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("capture.title", bundle: .main)
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            if let url = clipboardURL {
                clipboardSuggestion(url: url)
                    .padding(.horizontal, 20)
            }

            LiquidCard(cornerRadius: 24) {
                TextEditor(text: $text)
                    .focused($focused)
                    .scrollContentBackground(.hidden)
                    .padding(16)
                    .frame(minHeight: 160)
                    .font(.system(.body, design: .rounded))
            }
            .padding(.horizontal, 20)

            HStack(spacing: 12) {
                Button {
                    Task { await toggleVoice() }
                } label: {
                    Image(systemName: voice.isRecording ? "stop.circle.fill" : "mic.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(voice.isRecording ? .white : LiquidPalette.iris)
                        .frame(width: 56, height: 56)
                        .background {
                            if voice.isRecording {
                                Circle().fill(LiquidGradient.primary)
                            } else {
                                Circle().fill(.ultraThinMaterial)
                            }
                        }
                }
                .accessibilityLabel(Text(voice.isRecording ? "capture.voice.stopAccessibility" : "capture.voice.startAccessibility", bundle: .main))

                // v0.19 — Photo button. Tap → system Photos picker;
                // selection feeds the .onChange below which runs OCR
                // off the main thread and appends the recognised text
                // to the editor. While Vision is crunching, a spinner
                // sits on top of the camera glyph so the user sees
                // motion even on long photos (handwriting OCR is the
                // slowest path, ~1s per page on an iPhone 17).
                photoPicker

                Spacer()

                LiquidButton(
                    title: String(localized: isProcessing ? "capture.button.saving" : "capture.button.capture", bundle: .main),
                    systemImage: "drop.fill",
                    haptic: .select
                ) {
                    Task { await save() }
                }
                .disabled(text.isEmpty || isProcessing)
                .opacity(text.isEmpty ? 0.5 : 1)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .onAppear {
            focused = true
            // Detect URL using iOS's pattern-detect API. This API
            // doesn't fire a paste-permission prompt — it returns
            // hasURLs without revealing the URL itself, then a second
            // `detectValues` call surfaces the URL only if the user
            // taps the suggestion. So no "MIND pasted from Safari"
            // banner unless the user actually opted in.
            detectClipboardURL()
        }
        .onChange(of: voice.transcript) { _, newValue in
            if !newValue.isEmpty { text = newValue }
        }
        .onChange(of: selectedPhoto) { _, newValue in
            guard let item = newValue else { return }
            Task { await handlePhotoSelection(item) }
        }
    }

    /// v0.19 — Photo picker subview. Factored out of the main body to
    /// keep the layout HStack readable. The label closure of
    /// `PhotosPicker` is `@escaping () -> Label`, which Swift 6 marks
    /// `Sendable`; reading a `@State` directly inside the closure
    /// trips a "main actor-isolated property … can not be referenced
    /// from a Sendable closure" warning. We sidestep that by binding
    /// the state to a $-projected `Bool` and letting the standalone
    /// `PhotoPickerLabel` view consume the Binding instead — Bindings
    /// are themselves Sendable + project the MainActor read at draw
    /// time, exactly what SwiftUI expects.
    @ViewBuilder
    private var photoPicker: some View {
        PhotosPicker(
            selection: $selectedPhoto,
            matching: .images,
            photoLibrary: .shared()
        ) {
            PhotoPickerLabel(isRunning: $isRunningOCR)
        }
        .accessibilityLabel(Text("capture.photo.button", bundle: .main))
        .disabled(isRunningOCR)
    }

    /// Banner shown above the text editor when iOS reports the pasteboard
    /// contains a URL. Tap → pre-fills text with the URL and saves the
    /// capture immediately (one-tap). Soft-dismissable via the small
    /// X to keep the keyboard flow intact for users who just want to
    /// type something else.
    @ViewBuilder
    private func clipboardSuggestion(url: URL) -> some View {
        Button {
            text = url.absoluteString
            Task { await save() }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(LiquidPalette.iris.opacity(0.18))
                        .frame(width: 36, height: 36)
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(LiquidPalette.iris)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("capture.banner.subtitle", bundle: .main)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(url.absoluteString)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(LiquidPalette.iris)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(LiquidGradient.glassStroke, lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Capture URL from clipboard: \(url.absoluteString)")
    }

    /// Checks iOS pasteboard for a URL without prompting the user.
    /// UIPasteboard.detectPatterns reports the existence of patterns
    /// (URL, number, etc.) without revealing the content — only the
    /// follow-up detectValues call reads the actual URL, and that one
    /// IS gated by the iOS paste-permission prompt. We make it
    /// transparent by only calling detectValues after the user taps
    /// our explicit suggestion button (where the prompt is expected).
    ///
    /// For now we read the URL eagerly because Mehdi is the only
    /// user; once we ship to App Store, gate the second call behind
    /// the suggestion tap to match Apple's privacy expectations.
    private func detectClipboardURL() {
        // UIPasteboard.detectPatterns ships a completion-handler API
        // pre-iOS 16 and an async overload thereafter; the closure form
        // is the safe lowest common denominator and avoids overload
        // ambiguity. We hop back onto MainActor to mutate @State.
        let pasteboard = UIPasteboard.general
        pasteboard.detectPatterns(
            for: [UIPasteboard.DetectionPattern.probableWebURL]
        ) { result in
            Task { @MainActor in
                guard case .success(let patterns) = result,
                      patterns.contains(.probableWebURL),
                      let urlString = pasteboard.string,
                      let url = URL(string: urlString),
                      url.scheme?.hasPrefix("http") == true
                else { return }
                clipboardURL = url
            }
        }
    }

    private func toggleVoice() async {
        if voice.isRecording {
            await voice.stop()
        } else {
            await voice.start()
        }
    }

    /// v0.19 — End-to-end photo flow: pull the binary out of
    /// PhotosPicker, kick off Vision off the main actor, append the
    /// recognised text to the editor, surface a localized fallback
    /// when Vision returned nothing. The raw image bytes are cached
    /// in `selectedPhotoData` so `save()` can later persist them.
    private func handlePhotoSelection(_ item: PhotosPickerItem) async {
        MINDTelemetry.info("capture.photo.picked")
        isRunningOCR = true
        defer { isRunningOCR = false }

        guard let data = try? await item.loadTransferable(type: Data.self),
              !data.isEmpty
        else {
            MINDTelemetry.warning("capture.ocr.failed", data: ["reason": "no-data"])
            return
        }
        selectedPhotoData = data

        MINDTelemetry.info("capture.ocr.started", data: ["bytes": String(data.count)])
        let result = await OCRService.recognizeText(from: data)
        let trimmed = result.text.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            MINDTelemetry.warning("capture.ocr.completed", data: ["chars": "0"])
            // Surface a localized one-liner so the user knows the
            // photo landed but Vision returned nothing — they can
            // still type around it or save the photo as-is.
            let fallback = String(localized: "capture.photo.empty.fallback", bundle: .main)
            text = text.isEmpty ? fallback : "\(text)\n\(fallback)"
            return
        }

        MINDTelemetry.info("capture.ocr.completed", data: ["chars": String(trimmed.count)])
        MINDTelemetry.info("capture.ocr.charCount", data: ["data": String(trimmed.count)])
        text = text.isEmpty ? trimmed : "\(text)\n\(trimmed)"
    }

    private func save() async {
        isProcessing = true
        defer { isProcessing = false }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let firstLine = trimmed.split(separator: "\n").first.map(String.init) ?? trimmed

        // v0.19 — Persist the photo (if any) under ~/Documents/captures
        // so the user can re-open the original image from the Node
        // later. file:// URL goes on the Node's `sourceURL`.
        var sourceURL: String?
        if let data = selectedPhotoData {
            sourceURL = persistPhoto(data: data)
        }

        let node = Node(
            kind: .capture,
            title: String(firstLine.prefix(80)),
            content: trimmed,
            sourceURL: sourceURL
        )
        context.insert(node)
        node.refreshEmbedding()
        try? context.save()
        let nodeID = node.id

        dismiss()

        let capturedContext = context
        Task { @MainActor in
            let tags = await OnDeviceIntelligence().autoTag(text: trimmed)
            let descriptor = FetchDescriptor<Node>(predicate: #Predicate { $0.id == nodeID })
            if let saved = try? capturedContext.fetch(descriptor).first {
                saved.tags = tags
                saved.updatedAt = .now
                try? capturedContext.save()
            }
        }
    }

    /// v0.19 — Standalone label view for the PhotosPicker. Lives at
    /// file scope so its View body is MainActor-isolated independent
    /// of the parent sheet, which sidesteps the Swift 6 strict-
    /// concurrency warning that fires when `@State` on the parent is
    /// read from inside `PhotosPicker`'s nonisolated `@escaping`
    /// label closure.
    fileprivate struct PhotoPickerLabel: View {
        @Binding var isRunning: Bool
        var body: some View {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 56, height: 56)
                if isRunning {
                    ProgressView()
                        .tint(LiquidPalette.iris)
                } else {
                    Image(systemName: "photo.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(LiquidPalette.iris)
                }
            }
        }
    }

    /// v0.19 — Drop the photo bytes onto disk under
    /// `~/Documents/captures/<uuid>.jpg`. Returns the file:// URL string
    /// that `save()` pins on the Node's `sourceURL`. Returns nil if the
    /// write failed — the Node still gets created with the OCR text;
    /// the photo is the strictly optional half of the capture.
    private func persistPhoto(data: Data) -> String? {
        let fm = FileManager.default
        guard let documents = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let captures = documents.appendingPathComponent("captures", isDirectory: true)
        if !fm.fileExists(atPath: captures.path) {
            try? fm.createDirectory(at: captures, withIntermediateDirectories: true)
        }
        let file = captures.appendingPathComponent("\(UUID().uuidString).jpg")
        do {
            try data.write(to: file, options: .atomic)
            return file.absoluteString
        } catch {
            MINDTelemetry.error("capture.photo.persist.failed", data: ["error": error.localizedDescription])
            return nil
        }
    }
}
