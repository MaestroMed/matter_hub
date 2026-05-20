import Foundation
import SwiftData
import GraphCore
import Intelligence

@MainActor
@Observable
public final class ChatModel {
    public var messages: [ChatMessage] = []
    public var input: String = ""
    public var isSending: Bool = false
    public var lastError: String?

    private let cloud: CloudIntelligence

    public init(cloud: CloudIntelligence = CloudIntelligence()) {
        self.cloud = cloud
    }

    public func send(contextNodes: [Node] = []) async {
        let prompt = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isSending else { return }

        let userMessage = ChatMessage(role: .user, content: prompt)
        messages.append(userMessage)
        input = ""
        isSending = true
        lastError = nil

        do {
            let answer = try await cloud.complete(prompt: prompt, contextNodes: contextNodes)
            messages.append(ChatMessage(role: .assistant, content: answer))
        } catch {
            lastError = error.localizedDescription
            messages.append(ChatMessage(
                role: .assistant,
                content: "⚠️ \(error.localizedDescription)"
            ))
        }

        isSending = false
    }

    public func reset() {
        messages.removeAll()
        input = ""
        lastError = nil
    }
}
