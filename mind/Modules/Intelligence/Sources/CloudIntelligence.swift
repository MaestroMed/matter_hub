import Foundation
import GraphCore

public enum CloudIntelligenceError: Error, LocalizedError, Sendable {
    case missingAPIKey
    case requestFailed(Int, String)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Set ANTHROPIC_API_KEY in Settings → MIND → API Key."
        case .requestFailed(let code, let message):
            return "Anthropic API error \(code): \(message)"
        case .invalidResponse:
            return "Unreadable response from Anthropic API."
        }
    }
}

@MainActor
@Observable
public final class CloudIntelligence {
    public var model: String = "claude-sonnet-4-6"
    public var maxTokens: Int = 1024

    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let apiVersion = "2023-06-01"

    public init() {}

    public func complete(prompt: String, contextNodes: [Node] = []) async throws -> String {
        guard let key = APIKeyStore.read() else {
            throw CloudIntelligenceError.missingAPIKey
        }

        var systemPrompt = "You are MIND, a personal second-brain assistant. Reply concisely. Match the user's language."
        if !contextNodes.isEmpty {
            let context = contextNodes
                .prefix(20)
                .map { "[\($0.kind.rawValue)] \($0.title): \($0.content)" }
                .joined(separator: "\n---\n")
            systemPrompt += "\n\nRELEVANT CONTEXT FROM USER'S GRAPH:\n\(context)"
        }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": prompt]
            ],
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CloudIntelligenceError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? ""
            throw CloudIntelligenceError.requestFailed(http.statusCode, message)
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let contentArray = json["content"] as? [[String: Any]],
            let firstText = contentArray.first(where: { ($0["type"] as? String) == "text" })?["text"] as? String
        else {
            throw CloudIntelligenceError.invalidResponse
        }
        return firstText
    }
}
