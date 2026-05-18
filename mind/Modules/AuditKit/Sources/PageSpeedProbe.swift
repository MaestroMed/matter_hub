import Foundation

public enum PageSpeedProbeError: Error, LocalizedError, Sendable {
    case invalidURL
    case requestFailed(Int, String)
    case decodingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "URL invalide pour PageSpeed."
        case .requestFailed(let code, let message):
            return "PageSpeed API erreur \(code): \(message.prefix(160))"
        case .decodingFailed(let message):
            return "PageSpeed: décodage impossible (\(message.prefix(120)))"
        }
    }
}

/// Calls Google PageSpeed Insights v5 — public quota, no API key required.
/// Returns the four Lighthouse category scores plus the three Core Web
/// Vitals for the given URL, mobile strategy by default.
public enum PageSpeedProbe {
    public enum Strategy: String, Sendable {
        case mobile
        case desktop
    }

    public static func fetch(
        for url: URL,
        strategy: Strategy = .mobile
    ) async throws -> AuditReport.PerformanceMetrics {
        var components = URLComponents(string: "https://www.googleapis.com/pagespeedonline/v5/runPagespeed")!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "url", value: url.absoluteString),
            URLQueryItem(name: "strategy", value: strategy.rawValue),
        ]
        for category in ["performance", "seo", "accessibility", "best-practices"] {
            items.append(URLQueryItem(name: "category", value: category.uppercased()))
        }
        components.queryItems = items

        guard let requestURL = components.url else {
            throw PageSpeedProbeError.invalidURL
        }

        var request = URLRequest(url: requestURL)
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PageSpeedProbeError.requestFailed(0, "no http response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw PageSpeedProbeError.requestFailed(http.statusCode, body)
        }

        do {
            let payload = try JSONDecoder().decode(PageSpeedResponse.self, from: data)
            return AuditReport.PerformanceMetrics(
                performanceScore: payload.score(.performance),
                seoScore: payload.score(.seo),
                accessibilityScore: payload.score(.accessibility),
                bestPracticesScore: payload.score(.bestPractices),
                largestContentfulPaintSeconds: payload.lcpSeconds,
                interactionToNextPaintMs: payload.inpMs,
                cumulativeLayoutShift: payload.cls
            )
        } catch {
            throw PageSpeedProbeError.decodingFailed(String(describing: error))
        }
    }
}

// MARK: - JSON shapes

private struct PageSpeedResponse: Decodable {
    let lighthouseResult: Lighthouse

    enum Category {
        case performance, seo, accessibility, bestPractices
        var key: String {
            switch self {
            case .performance:   return "performance"
            case .seo:           return "seo"
            case .accessibility: return "accessibility"
            case .bestPractices: return "best-practices"
            }
        }
    }

    func score(_ category: Category) -> Int {
        guard let raw = lighthouseResult.categories[category.key]?.score else { return 0 }
        return Int((raw * 100).rounded())
    }

    var lcpSeconds: Double? {
        lighthouseResult.audits["largest-contentful-paint"]?.numericValue.map { $0 / 1000.0 }
    }

    var inpMs: Int? {
        lighthouseResult.audits["interaction-to-next-paint"]?.numericValue.map { Int($0) }
    }

    var cls: Double? {
        lighthouseResult.audits["cumulative-layout-shift"]?.numericValue
    }
}

private struct Lighthouse: Decodable {
    let categories: [String: ScoreEntry]
    let audits: [String: AuditEntry]
}

private struct ScoreEntry: Decodable {
    let score: Double?
}

private struct AuditEntry: Decodable {
    let numericValue: Double?
}
