import SwiftUI
import SwiftData
import DesignSystem
import GraphCore
import Intelligence

public struct QuickCaptureSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""
    @State private var isProcessing = false
    @State private var voice = VoiceCapture()
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

                Spacer()

                LiquidButton(title: isProcessing ? "Saving…" : "Capture", systemImage: "drop.fill") {
                    Task { await save() }
                }
                .disabled(text.isEmpty || isProcessing)
                .opacity(text.isEmpty ? 0.5 : 1)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .onAppear { focused = true }
        .onChange(of: voice.transcript) { _, newValue in
            if !newValue.isEmpty { text = newValue }
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
