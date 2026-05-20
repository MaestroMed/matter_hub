import Foundation

/// Looks up the prospect's public Trustpilot profile by domain. Returns
/// the aggregate star rating + number of reviews — strong social-proof
/// signal Mehdi can quote in his pitch.
public enum TrustpilotProbe {
    public static func fetch(for url: URL) async throws -> TrustFindings {
        guard let host = url.host(percentEncoded: false) else {
            return TrustFindings(
                trustpilotScore: nil,
                trustpilotReviewCount: nil,
                trustpilotProfileURL: nil
            )
        }
        let clean = host.replacingOccurrences(of: "www.", with: "")
        guard let profileURL = URL(string: "https://www.trustpilot.com/review/\(clean)") else {
            return TrustFindings(
                trustpilotScore: nil,
                trustpilotReviewCount: nil,
                trustpilotProfileURL: nil
            )
        }

        let html: String
        do {
            html = try await HTMLProbe.fetchLowercased(profileURL)
        } catch {
            return TrustFindings(
                trustpilotScore: nil,
                trustpilotReviewCount: nil,
                trustpilotProfileURL: nil
            )
        }

        // Trustpilot embeds its data in JSON-LD AggregateRating. We
        // extract the two numeric values via lightweight string scans
        // rather than parsing the full document.
        let score = extractDouble(after: "\"ratingvalue\":", in: html)
        let count = extractInt(after: "\"reviewcount\":", in: html)

        // Only surface the profile URL when we actually got numbers —
        // otherwise we'd be linking to "page does not exist".
        let hasSignal = score != nil || count != nil
        return TrustFindings(
            trustpilotScore: score,
            trustpilotReviewCount: count,
            trustpilotProfileURL: hasSignal ? profileURL : nil
        )
    }

    private static func extractDouble(after needle: String, in source: String) -> Double? {
        guard let range = source.range(of: needle) else { return nil }
        let rest = source[range.upperBound...]
        let digits = rest.prefix { $0.isNumber || $0 == "." || $0 == "\"" }
            .filter { $0 != "\"" }
        return Double(digits)
    }

    private static func extractInt(after needle: String, in source: String) -> Int? {
        guard let range = source.range(of: needle) else { return nil }
        let rest = source[range.upperBound...]
        let digits = rest.prefix { $0.isNumber || $0 == "\"" }
            .filter { $0 != "\"" }
        return Int(digits)
    }
}
