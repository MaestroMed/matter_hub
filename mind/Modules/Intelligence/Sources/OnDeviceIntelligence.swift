import Foundation
import NaturalLanguage

@MainActor
@Observable
public final class OnDeviceIntelligence {
    public init() {}

    public func autoTag(text: String) async -> [String] {
        fallbackTags(from: text)
    }

    public func summarize(text: String) async -> String? {
        nil
    }

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
