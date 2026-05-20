import Foundation
import GraphCore

/// v1.0-alpha.8 — Lighthouse score snapshot tailored for the cockpit
/// grid. Mirrors the AuditKit `AuditReport.PerformanceMetrics` fields
/// the user actually sees on a project card; kept independent so the
/// audit pipeline can evolve without dragging this surface with it.
///
/// `fetchedAt` is the device-local timestamp the probe completed at —
/// the cache TTL is derived from it.
public struct LighthouseScore: Sendable, Codable, Hashable {
    public let performance: Int       // 0-100
    public let accessibility: Int
    public let bestPractices: Int
    public let seo: Int
    public let lcpSeconds: Double
    public let inpMs: Int
    public let cls: Double
    public let fetchedAt: Date

    public init(
        performance: Int,
        accessibility: Int,
        bestPractices: Int,
        seo: Int,
        lcpSeconds: Double,
        inpMs: Int,
        cls: Double,
        fetchedAt: Date = .now
    ) {
        self.performance = performance
        self.accessibility = accessibility
        self.bestPractices = bestPractices
        self.seo = seo
        self.lcpSeconds = lcpSeconds
        self.inpMs = inpMs
        self.cls = cls
        self.fetchedAt = fetchedAt
    }

    /// Average of the four categorical scores. Used by the
    /// ProjectCard pill aggregate.
    public var overall: Int {
        let sum = performance + accessibility + bestPractices + seo
        return Int(Double(sum) / 4.0)
    }
}

/// v1.0-alpha.8 — Failure modes the UI cares about. Same shape as
/// `VercelClientError` / `GitHubClientError` for cross-provider
/// symmetry in the call sites.
public enum LighthouseProbeError: Error, Sendable, Equatable {
    case invalidHost
    case http(Int)
    case decode
    case network(String)

    public static func == (lhs: LighthouseProbeError, rhs: LighthouseProbeError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidHost, .invalidHost), (.decode, .decode):
            return true
        case let (.http(a), .http(b)):
            return a == b
        case let (.network(a), .network(b)):
            return a == b
        default:
            return false
        }
    }
}

/// v1.0-alpha.8 — Lightweight wrapper around Google PageSpeed Insights
/// v5. The endpoint is the same one AuditKit's `PageSpeedProbe` hits,
/// but the response shape exposed here is the 4-cell grid the cockpit
/// renders — perf / a11y / bp / seo + the 3 Core Web Vitals — rather
/// than the full audit pipeline's `PerformanceMetrics`.
///
/// No API key required for the public quota (low-traffic personal
/// use). Soft-fails like the other clients in this module.
public actor LighthouseProbe {
    public static let shared = LighthouseProbe()

    public enum Strategy: String, Sendable {
        case mobile
        case desktop
    }

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Calls PageSpeed Insights v5 for the given host. Strips a
    /// leading `https://` or `http://` scheme — the API accepts a
    /// fully-qualified URL only.
    public func score(
        for host: String,
        strategy: Strategy = .mobile
    ) async throws -> LighthouseScore {
        guard let url = Self.endpoint(forHost: host, strategy: strategy) else {
            throw LighthouseProbeError.invalidHost
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 60

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LighthouseProbeError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw LighthouseProbeError.decode
        }
        guard (200..<300).contains(http.statusCode) else {
            throw LighthouseProbeError.http(http.statusCode)
        }
        do {
            let dto = try JSONDecoder().decode(PageSpeedDTO.self, from: data)
            return dto.score
        } catch {
            throw LighthouseProbeError.decode
        }
    }

    /// Builds the PageSpeed Insights endpoint URL for a given host
    /// + strategy. Pure helper exposed for tests.
    public static func endpoint(forHost host: String, strategy: Strategy = .mobile) -> URL? {
        var trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.hasPrefix("http://") && !trimmed.hasPrefix("https://") {
            trimmed = "https://" + trimmed
        }
        var components = URLComponents(string: "https://www.googleapis.com/pagespeedonline/v5/runPagespeed")!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "url", value: trimmed),
            URLQueryItem(name: "strategy", value: strategy.rawValue),
        ]
        for category in ["PERFORMANCE", "SEO", "ACCESSIBILITY", "BEST_PRACTICES"] {
            items.append(URLQueryItem(name: "category", value: category))
        }
        components.queryItems = items
        return components.url
    }
}

// MARK: - Wire format

private struct PageSpeedDTO: Decodable {
    let lighthouseResult: Lighthouse

    struct Lighthouse: Decodable {
        let categories: [String: ScoreEntry]
        let audits: [String: AuditEntry]
    }

    struct ScoreEntry: Decodable {
        let score: Double?
    }

    struct AuditEntry: Decodable {
        let numericValue: Double?
    }

    var score: LighthouseScore {
        func categoryScore(_ key: String) -> Int {
            guard let raw = lighthouseResult.categories[key]?.score else { return 0 }
            return Int((raw * 100).rounded())
        }
        let lcp = (lighthouseResult.audits["largest-contentful-paint"]?.numericValue ?? 0) / 1000.0
        let inp = Int(lighthouseResult.audits["interaction-to-next-paint"]?.numericValue ?? 0)
        let cls = lighthouseResult.audits["cumulative-layout-shift"]?.numericValue ?? 0
        return LighthouseScore(
            performance: categoryScore("performance"),
            accessibility: categoryScore("accessibility"),
            bestPractices: categoryScore("best-practices"),
            seo: categoryScore("seo"),
            lcpSeconds: lcp,
            inpMs: inp,
            cls: cls,
            fetchedAt: .now
        )
    }
}
