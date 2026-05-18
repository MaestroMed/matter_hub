import Foundation

public enum AppStoreProbeError: Error, LocalizedError, Sendable {
    case requestFailed(Int)
    case decodingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .requestFailed(let code): return "App Store: échec (\(code))."
        case .decodingFailed(let msg): return "App Store: décodage \(msg.prefix(120))."
        }
    }
}

/// Public iTunes Search API — no key, ~20 req/min per IP. We search by
/// brand name, keep results from the matching seller, and report whether
/// a native iOS app exists for the prospect (and how well-rated).
public enum AppStoreProbe {
    public static func search(
        name: String,
        country: String = "us"
    ) async throws -> MobileFindings {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return MobileFindings(hasIOSApp: false)
        }

        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: trimmed),
            URLQueryItem(name: "entity", value: "software"),
            URLQueryItem(name: "country", value: country),
            URLQueryItem(name: "limit", value: "5"),
        ]
        guard let url = components.url else {
            return MobileFindings(hasIOSApp: false)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppStoreProbeError.requestFailed(0)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AppStoreProbeError.requestFailed(http.statusCode)
        }

        let payload: SearchResponse
        do {
            payload = try JSONDecoder().decode(SearchResponse.self, from: data)
        } catch {
            throw AppStoreProbeError.decodingFailed(String(describing: error))
        }

        guard let best = bestMatch(name: trimmed, in: payload.results) else {
            return MobileFindings(hasIOSApp: false)
        }

        return MobileFindings(
            hasIOSApp: true,
            appName: best.trackName,
            sellerName: best.sellerName,
            averageRating: best.averageUserRating,
            ratingCount: best.userRatingCount,
            primaryGenre: best.primaryGenreName
        )
    }

    private static func bestMatch(
        name: String,
        in results: [SearchResult]
    ) -> SearchResult? {
        let needle = name.lowercased()
        // Prefer a seller-name or app-name that contains the needle. Fall
        // back to the most-rated result so we don't surface a tiny clone.
        let matches = results.filter {
            $0.sellerName.lowercased().contains(needle) ||
            $0.trackName.lowercased().contains(needle)
        }
        if let pick = matches.max(by: { ($0.userRatingCount ?? 0) < ($1.userRatingCount ?? 0) }) {
            return pick
        }
        return results.max(by: { ($0.userRatingCount ?? 0) < ($1.userRatingCount ?? 0) })
    }
}

// MARK: - JSON shapes

private struct SearchResponse: Decodable {
    let results: [SearchResult]
}

private struct SearchResult: Decodable {
    let trackName: String
    let sellerName: String
    let averageUserRating: Double?
    let userRatingCount: Int?
    let primaryGenreName: String?
}
