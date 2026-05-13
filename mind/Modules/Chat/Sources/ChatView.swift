import SwiftUI
import DesignSystem

public struct ChatView: View {
    @State private var model = ChatModel()
    @FocusState private var inputFocused: Bool

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            header
            messageList
            inputBar
        }
        .background {
            LiquidBackground().ignoresSafeArea()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Ask MIND")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                Text("Your second brain, listening.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !model.messages.isEmpty {
                Button {
                    withAnimation(LiquidMetrics.spring) { model.reset() }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if model.messages.isEmpty {
                        emptyState
                            .padding(.top, 80)
                    } else {
                        ForEach(model.messages) { msg in
                            MessageBubble(message: msg)
                                .id(msg.id)
                        }
                        if model.isSending {
                            TypingBubble()
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .onChange(of: model.messages.count) { _, _ in
                if let last = model.messages.last {
                    withAnimation(LiquidMetrics.spring) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "drop.fill")
                .font(.system(size: 56))
                .foregroundStyle(LiquidGradient.primary)
            Text("What's on your mind?")
                .font(.system(.title3, design: .rounded, weight: .semibold))
            Text("Ask anything. Your graph is the context.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask anything…", text: $model.input, axis: .vertical)
                .focused($inputFocused)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .rounded))
                .lineLimit(1...5)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background {
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(LiquidGradient.glassStroke, lineWidth: 1)
                        }
                }

            Button {
                inputFocused = false
                Task { await model.send() }
            } label: {
                ZStack {
                    Circle()
                        .fill(LiquidGradient.primary)
                        .frame(width: 44, height: 44)
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                }
                .shadow(color: LiquidPalette.iris.opacity(0.4), radius: 10, y: 4)
                .opacity(canSend ? 1 : 0.4)
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private var canSend: Bool {
        !model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.isSending
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(message.content)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(message.role == .user ? .white : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background {
                    if message.role == .user {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(LiquidGradient.primary)
                    } else {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay {
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .stroke(LiquidGradient.glassStroke, lineWidth: 1)
                            }
                    }
                }
                .shadow(
                    color: message.role == .user ? LiquidPalette.iris.opacity(0.3) : .black.opacity(0.05),
                    radius: 8,
                    y: 3
                )
            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }
}

private struct TypingBubble: View {
    @State private var phase: Double = 0

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(LiquidPalette.iris)
                    .frame(width: 8, height: 8)
                    .opacity(0.4 + 0.6 * sin(phase + Double(i) * 0.6))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(LiquidGradient.glassStroke, lineWidth: 1)
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 60)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }
}
