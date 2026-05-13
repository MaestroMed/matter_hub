import Foundation
import NaturalLanguage

#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
@Observable
public final class OnDeviceIntelligence {
    public init() {}

    public func autoTag(text: String) async -> [String] {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            do {
                let session = LanguageModelSession()
                let response = try await session.respond(to: """
                Extract 3 to 6 lowercase single-word tags from the following note. \
                Reply with a comma-separated list, nothing else.

                NOTE:
                \(text)
                """)
                return response.content
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    .filter { !$0.isEmpty }
            } catch {
                return fallbackTags(from: text)
            }
        }
        #endif
        return fallbackTags(from: text)
    }

    public func summarize(text: String) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            do {
                let session = LanguageModelSession()
                let response = try await session.respond(to: """
                Summarize the following in one short sentence.

                \(text)
                """)
                return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }

    private func fallbackTags(from text: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.nameType, .lexicalClass])
        tagger.string = text
        var tags: Set<String> = []
        let range = text.startIndex..<text.endIndex
        tagger.enumerateTags(in: range, unit: .word, scheme: .lexicalClass, options: [.omitWhitespace, .omitPunctuation]) { tag, tokenRange in
            if tag == .noun {
                tags.insert(String(text[tokenRange]).lowercased())
            }
            return tags.count < 6
        }
        return Array(tags.prefix(6))
    }
}
