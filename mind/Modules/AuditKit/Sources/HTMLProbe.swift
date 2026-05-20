import Foundation

/// Shared HTML fetcher used by the second-wave probes that need to look
/// at the home page itself (OG tags, Schema.org, analytics, payment,
/// cookie banner). Centralised so we only pay one HTTP round trip even
/// when multiple probes need the markup, and so every probe applies the
/// same browser-like User-Agent (some sites cloak away from "URLSession").
public enum HTMLProbe {
    public enum HTMLProbeError: Error {
        case requestFailed(Int)
        case nonTextResponse
    }

    /// Fetches the URL once and returns the raw HTML body as a String
    /// (UTF-8 lossy if the server's charset is exotic).
    public static func fetch(_ url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw HTMLProbeError.requestFailed(0)
        }
        guard (200..<400).contains(http.statusCode) else {
            throw HTMLProbeError.requestFailed(http.statusCode)
        }
        if let string = String(data: data, encoding: .utf8) { return string }
        return String(data: data, encoding: .isoLatin1) ?? ""
    }

    /// Lowercased HTML body, useful for case-insensitive keyword scans
    /// (cookie banners, analytics SDK names, payment processors).
    public static func fetchLowercased(_ url: URL) async throws -> String {
        let raw = try await fetch(url)
        return raw.lowercased()
    }

    /// Returns the response headers of a single HEAD request — used by
    /// the CDN probe to read Server / X-Cache / CF-Ray etc.
    public static func headers(for url: URL) async throws -> [AnyHashable: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 15

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw HTMLProbeError.requestFailed(0)
        }
        return http.allHeaderFields
    }
}
