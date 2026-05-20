import Foundation

public enum SecurityHeadersProbeError: Error, LocalizedError, Sendable {
    case invalidResponse
    case requestFailed(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: return "No HTTP response."
        case .requestFailed(let code): return "Request failed (\(code))."
        }
    }
}

/// Lightweight Mozilla-Observatory-style scoring. Fires a single HEAD
/// (falls back to GET if the server doesn't answer HEAD), reads the
/// security-related response headers, and grades the result without any
/// third-party API. URLSession's own TLS validation tells us if the cert
/// is at least basic-valid.
public enum SecurityHeadersProbe {
    private struct HeaderRule: Sendable {
        let name: String
        let weight: Int
        /// Optional value predicate — when present, the header has to match
        /// to count. None == "any non-empty value passes".
        let validate: (@Sendable (String) -> Bool)?
    }

    private static let rules: [HeaderRule] = [
        HeaderRule(name: "Strict-Transport-Security", weight: 20, validate: { $0.lowercased().contains("max-age=") }),
        HeaderRule(name: "Content-Security-Policy", weight: 20, validate: nil),
        HeaderRule(name: "X-Frame-Options", weight: 15, validate: { ["deny", "sameorigin"].contains($0.lowercased()) }),
        HeaderRule(name: "X-Content-Type-Options", weight: 15, validate: { $0.lowercased().contains("nosniff") }),
        HeaderRule(name: "Referrer-Policy", weight: 15, validate: nil),
        HeaderRule(name: "Permissions-Policy", weight: 15, validate: nil),
    ]

    public static func fetch(for url: URL) async throws -> SecurityFindings {
        let (tlsValid, headers) = try await fetchHeaders(for: url)

        var score = 0
        var present: [String] = []
        var missing: [String] = []

        for rule in rules {
            if let raw = headers.value(forCanonical: rule.name),
               !raw.trimmingCharacters(in: .whitespaces).isEmpty,
               (rule.validate?(raw) ?? true) {
                score += rule.weight
                present.append(rule.name)
            } else {
                missing.append(rule.name)
            }
        }

        return SecurityFindings(
            grade: grade(for: score),
            score: score,
            presentHeaders: present,
            missingHeaders: missing,
            tlsValid: tlsValid
        )
    }

    // MARK: - Networking

    private static func fetchHeaders(
        for url: URL
    ) async throws -> (tlsValid: Bool, headers: HeaderBag) {
        var headRequest = URLRequest(url: url)
        headRequest.httpMethod = "HEAD"
        headRequest.timeoutInterval = 25

        if let (_, response) = try? await URLSession.shared.data(for: headRequest),
           let http = response as? HTTPURLResponse,
           (200..<400).contains(http.statusCode) {
            return (true, HeaderBag(raw: http.allHeaderFields))
        }

        // Many CDNs only answer GET. Fall back to a 0-byte GET via range.
        var getRequest = URLRequest(url: url)
        getRequest.httpMethod = "GET"
        getRequest.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        getRequest.timeoutInterval = 25

        let (_, response) = try await URLSession.shared.data(for: getRequest)
        guard let http = response as? HTTPURLResponse else {
            throw SecurityHeadersProbeError.invalidResponse
        }
        guard (200..<400).contains(http.statusCode) else {
            throw SecurityHeadersProbeError.requestFailed(http.statusCode)
        }
        return (true, HeaderBag(raw: http.allHeaderFields))
    }

    private static func grade(for score: Int) -> String {
        switch score {
        case 95...:   return "A+"
        case 80..<95: return "A"
        case 65..<80: return "B"
        case 50..<65: return "C"
        case 30..<50: return "D"
        default:      return "F"
        }
    }
}

/// Case-insensitive header bag — `HTTPURLResponse.allHeaderFields` is
/// case-sensitive when typed as `[AnyHashable: Any]` so we normalize once.
private struct HeaderBag {
    private let map: [String: String]

    init(raw: [AnyHashable: Any]) {
        var dict: [String: String] = [:]
        for (key, value) in raw {
            guard let k = key as? String else { continue }
            dict[k.lowercased()] = "\(value)"
        }
        self.map = dict
    }

    func value(forCanonical name: String) -> String? {
        map[name.lowercased()]
    }
}
