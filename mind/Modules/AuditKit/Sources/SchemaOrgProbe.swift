import Foundation

/// Detects Schema.org JSON-LD structured data in the home page. SEO
/// gold — Google uses it for rich results, FAQ snippets, product cards.
public enum SchemaOrgProbe {
    public static func fetch(for url: URL) async throws -> SchemaFindings {
        let html = try await HTMLProbe.fetch(url)
        let blocks = jsonLDBlocks(in: html)
        let types = blocks.flatMap(typeNames(in:))
        let uniqueTypes = Array(Set(types)).sorted()
        return SchemaFindings(
            hasJSONLD: !blocks.isEmpty,
            detectedTypes: uniqueTypes
        )
    }

    /// Pulls the raw inside-text of every `<script type="application/ld+json">`
    /// block in the document. Tolerant to whitespace and quote variations.
    private static func jsonLDBlocks(in html: String) -> [String] {
        let pattern = #"<script[^>]+type=["']application/ld\+json["'][^>]*>([\s\S]*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, options: [], range: range)
        return matches.compactMap { match -> String? in
            guard match.numberOfRanges >= 2,
                  let captureRange = Range(match.range(at: 1), in: html) else { return nil }
            return String(html[captureRange])
        }
    }

    /// Extracts every `"@type"` value from a JSON-LD block. Handles both
    /// single string types and arrays. Defensive against malformed JSON.
    private static func typeNames(in jsonLD: String) -> [String] {
        guard let data = jsonLD.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }
        var collected: [String] = []
        collectTypes(parsed, into: &collected)
        return collected
    }

    private static func collectTypes(_ node: Any, into collected: inout [String]) {
        if let dict = node as? [String: Any] {
            if let value = dict["@type"] {
                if let single = value as? String {
                    collected.append(single)
                } else if let many = value as? [String] {
                    collected.append(contentsOf: many)
                }
            }
            for entry in dict.values {
                collectTypes(entry, into: &collected)
            }
        } else if let array = node as? [Any] {
            for entry in array {
                collectTypes(entry, into: &collected)
            }
        }
    }
}
