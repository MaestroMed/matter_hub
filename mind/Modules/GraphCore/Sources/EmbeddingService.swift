import Foundation
import NaturalLanguage

/// On-device sentence embedding service backed by Apple's pre-trained
/// `NLEmbedding` (iOS 14+). Free, no network call, runs in milliseconds.
/// Used by Node.refreshEmbedding so every captured thought gets a vector
/// for future semantic search / connection-finding.
///
/// Lives in GraphCore (rather than Intelligence) so the data layer can
/// embed without taking a dependency on Intelligence — which would create
/// a cycle since Intelligence already depends on GraphCore.
public enum EmbeddingService {
    /// Returns a dense sentence-level embedding for the text, or nil when
    /// no model is available for the (detected or fallback) language.
    /// Typically 300-dim for the French and English Apple models.
    public static func embed(_ text: String) -> [Float]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let language = detectedLanguage(for: trimmed)
        if let embedding = NLEmbedding.sentenceEmbedding(for: language),
           let vector = embedding.vector(for: trimmed) {
            return vector.map { Float($0) }
        }
        // Fall back to French (the project's default) when the detected
        // language isn't supported by Apple's on-device models.
        if language != .french,
           let embedding = NLEmbedding.sentenceEmbedding(for: .french),
           let vector = embedding.vector(for: trimmed) {
            return vector.map { Float($0) }
        }
        return nil
    }

    /// Cosine similarity in [-1, 1], best for ranking nearest neighbours.
    public static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denom = sqrt(normA) * sqrt(normB)
        return denom > 0 ? dot / denom : 0
    }

    private static func detectedLanguage(for text: String) -> NLLanguage {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage ?? .french
    }
}

public extension Node {
    /// Recomputes the Node's embedding from its current title + content
    /// and stores it on the model. Cheap (a few ms on Apple Silicon) but
    /// the caller is responsible for `try? context.save()` afterward.
    func refreshEmbedding() {
        let combined = [title, content]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        self.embedding = EmbeddingService.embed(combined)
    }
}
