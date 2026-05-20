import Foundation

public enum OpenAIImageError: Error, LocalizedError, Sendable {
    case missingKey
    case requestFailed(Int, String?)
    case invalidResponse
    case noImageReturned

    public var errorDescription: String? {
        switch self {
        case .missingKey:
            return "Clé OpenAI manquante. Configure-la dans Settings → OpenAI API Key."
        case .requestFailed(let code, let body):
            return "OpenAI API a renvoyé \(code)" + (body.map { ". \($0.prefix(160))" } ?? ".")
        case .invalidResponse:
            return "OpenAI: réponse non-HTTP."
        case .noImageReturned:
            return "OpenAI: aucune image dans la réponse."
        }
    }
}

/// Thin async wrapper around the OpenAI Images endpoint targeting the
/// `gpt-image-2` model (May 2026). Returns raw PNG bytes so the caller
/// is free to persist, display, or share them however they want.
///
/// The key is read live from the Keychain via OpenAIAPIKeyStore on each
/// call — no caching, no leaking through state. If the user rotates the
/// key in Settings, the next generation picks it up immediately.
public struct OpenAIImageClient: Sendable {
    private let endpoint: URL
    private let model: String

    public init(
        endpoint: URL = URL(string: "https://api.openai.com/v1/images/generations")!,
        model: String = "gpt-image-2"
    ) {
        self.endpoint = endpoint
        self.model = model
    }

    public func generate(
        prompt: String,
        size: VisualSize,
        quality: OpenAIImageQuality
    ) async throws -> Data {
        guard let key = OpenAIAPIKeyStore.read(), !key.isEmpty else {
            throw OpenAIImageError.missingKey
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120  // high quality can take ~60s

        let payload: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "size": size.openAIValue,
            "quality": quality.rawValue,
            "n": 1,
            "response_format": "b64_json",
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIImageError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw OpenAIImageError.requestFailed(http.statusCode, body)
        }

        let decoded = try JSONDecoder().decode(GenerationsResponse.self, from: data)
        guard let b64 = decoded.data.first?.b64_json,
              let bytes = Data(base64Encoded: b64) else {
            throw OpenAIImageError.noImageReturned
        }
        return bytes
    }

    // MARK: - JSON shape

    private struct GenerationsResponse: Decodable {
        let data: [Item]
        struct Item: Decodable {
            // OpenAI returns one of (url, b64_json) depending on the
            // response_format requested. We always request b64_json so
            // the bytes stay local without a second HTTP round-trip.
            let b64_json: String?
        }
    }
}
