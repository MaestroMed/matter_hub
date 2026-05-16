import Foundation
import FoundationModels
import NaturalLanguage

@MainActor
@Observable
public final class OnDeviceIntelligence {
    public init() {}

    public var isAppleIntelligenceAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    public func autoTag(text: String) async -> [String] {
        fallbackTags(from: text)
    }

    public func summarize(text: String) async -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard SystemLanguageModel.default.isAvailable else { return nil }

        do {
            let session = LanguageModelSession(instructions: Self.summarizeInstructions)
            let response = try await session.respond(to: trimmed)
            let cleaned = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? nil : cleaned
        } catch {
            return nil
        }
    }

    private static let summarizeInstructions: String = """
        You summarize a single thought captured by the user in their
        personal second brain. Reply with one short, friendly sentence
        in the same language as the input. No quotes, no preamble, no
        bullet points.
        """

    private func fallbackTags(from text: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        var tags: Set<String> = []
        let range = text.startIndex..<text.endIndex
        tagger.enumerateTags(
            in: range,
            unit: .word,
            scheme: .lexicalClass,
            options: [.omitWhitespace, .omitPunctuation]
        ) { tag, tokenRange in
            if tag == .noun {
                tags.insert(String(text[tokenRange]).lowercased())
            }
            return tags.count < 6
        }
        return Array(tags.prefix(6))
    }
}
