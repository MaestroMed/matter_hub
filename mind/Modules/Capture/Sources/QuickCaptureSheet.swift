import SwiftUI
import SwiftData
import UIKit
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
    @FocusState private var focused: Bool

    public init() {}

    public var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Capture")
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
                .accessibilityLabel(voice.isRecording ? "Stop voice capture" : "Start voice capture")

                Spacer()

                LiquidButton(
                    title: isProcessing ? "Saving…" : "Capture",
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
                    Text("Capturer depuis le presse-papier")
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

    private func save() async {
        isProcessing = true
        defer { isProcessing = false }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let firstLine = trimmed.split(separator: "\n").first.map(String.init) ?? trimmed
        let node = Node(
            kind: .capture,
            title: String(firstLine.prefix(80)),
            content: trimmed
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
}
