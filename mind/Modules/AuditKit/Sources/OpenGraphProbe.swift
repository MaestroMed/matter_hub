import Foundation

/// Checks Open Graph + Twitter Card meta tag completeness. These drive
/// how the site previews in iMessage, Slack, LinkedIn, WhatsApp, etc.
/// Missing OG tags = your CTAs land as a naked URL.
public enum OpenGraphProbe {
    public static func fetch(for url: URL) async throws -> OpenGraphFindings {
        let html = try await HTMLProbe.fetch(url)
        let lower = html.lowercased()

        let hasTitle = contains(meta: "og:title", in: lower)
        let hasDescription = contains(meta: "og:description", in: lower)
        let hasImage = contains(meta: "og:image", in: lower)
        let hasType = contains(meta: "og:type", in: lower)
        let hasTwitterCard = contains(meta: "twitter:card", in: lower)

        let total = [hasTitle, hasDescription, hasImage, hasType, hasTwitterCard]
            .filter { $0 }.count
        let score = Int((Double(total) / 5.0 * 100).rounded())

        return OpenGraphFindings(
            hasTitle: hasTitle,
            hasDescription: hasDescription,
            hasImage: hasImage,
            hasType: hasType,
            hasTwitterCard: hasTwitterCard,
            completenessScore: score
        )
    }

    /// Loose check: looks for `<meta property="og:title"` or
    /// `<meta name="twitter:card"`. Many CMSes use either property or
    /// name; we accept both.
    private static func contains(meta name: String, in lowercasedHTML: String) -> Bool {
        let propertyPattern = "<meta property=\"\(name)\""
        let propertySingleQuote = "<meta property='\(name)'"
        let namePattern = "<meta name=\"\(name)\""
        let nameSingleQuote = "<meta name='\(name)'"
        return lowercasedHTML.contains(propertyPattern)
            || lowercasedHTML.contains(propertySingleQuote)
            || lowercasedHTML.contains(namePattern)
            || lowercasedHTML.contains(nameSingleQuote)
    }
}
