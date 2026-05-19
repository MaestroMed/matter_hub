import Foundation
import AuditKit
import GraphCore

/// Errors surfaced by `NotionClient`. Cases map 1-to-1 onto the
/// failure modes the UI cares about — the Settings "Test sync" button
/// and the AuditSheet "Sync to Notion" button both render the case as
/// a short toast.
public enum NotionClientError: Error, Sendable, Equatable {
    /// `NotionTokenStore.read()` returned nil — the user hasn't pasted
    /// an integration token yet.
    case noToken

    /// The Notion API returned 401 — token rejected. Either the token
    /// is malformed or has been revoked from the integration settings.
    case invalidToken

    /// Any other non-2xx response. The status code is preserved so the
    /// UI can surface it in error toasts.
    case http(Int)

    /// JSONSerialization or response decoding failed.
    case decoding

    /// URLSession-level transport failure (offline, TLS error, etc.).
    case transport(String)

    public static func == (lhs: NotionClientError, rhs: NotionClientError) -> Bool {
        switch (lhs, rhs) {
        case (.noToken, .noToken), (.invalidToken, .invalidToken), (.decoding, .decoding):
            return true
        case let (.http(a), .http(b)):
            return a == b
        case let (.transport(a), .transport(b)):
            return a == b
        default:
            return false
        }
    }
}

/// Actor that owns every outbound Notion API call.
///
/// Why an actor?
/// -------------
/// The client holds no mutable state beyond its `URLSession` reference
/// today, but keeping it as an actor leaves room for v0.11.x retry
/// queues, rate-limit accounting, and the eventual OAuth swap without
/// breaking call sites. Every call site already awaits the methods,
/// so the boundary stays clean.
public actor NotionClient {
    /// Shared instance used by Settings + AuditSheet. The UI never
    /// constructs its own — keeping a single instance means a future
    /// retry queue / rate-limit bucket can live on the actor without
    /// duplicating state.
    public static let shared = NotionClient()

    /// Notion API version pinned to the latest stable revision at the
    /// time MIND v0.11 ships. Notion guarantees forward compatibility
    /// for old `Notion-Version` headers, so pinning is the safe move.
    static let apiVersion: String = "2022-06-28"

    static let baseURL: URL = URL(string: "https://api.notion.com")!

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Public API

    /// POSTs an `AuditReport` to the configured Notion database. Returns
    /// the page URL on success so the UI can offer "Open in Notion".
    public func createAuditPage(
        _ report: AuditReport,
        in databaseID: String
    ) async throws -> String {
        guard let token = NotionTokenStore.read(), !token.isEmpty else {
            throw NotionClientError.noToken
        }
        let payload = NotionPageBuilder.buildPagePayload(for: report, databaseID: databaseID)
        let url = Self.baseURL.appendingPathComponent("v1/pages")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            throw NotionClientError.decoding
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw NotionClientError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw NotionClientError.decoding
        }
        switch http.statusCode {
        case 200..<300:
            // Notion returns the freshly-created page object as JSON;
            // we extract `url` so the caller can open it in Safari.
            // Falling back to a placeholder keeps the success path
            // working even if Notion ever changes the response shape.
            if
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let pageURL = json["url"] as? String
            {
                return pageURL
            }
            return "https://notion.so"
        case 401:
            throw NotionClientError.invalidToken
        default:
            throw NotionClientError.http(http.statusCode)
        }
    }

    /// GET `/v1/users/me`. Returns true on 200, false on 401, throws
    /// on anything else — used by Settings to surface the green/red
    /// dot next to the saved token.
    public func validateToken() async -> Bool {
        guard let token = NotionTokenStore.read(), !token.isEmpty else {
            return false
        }
        let url = Self.baseURL.appendingPathComponent("v1/users/me")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "Notion-Version")

        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return http.statusCode == 200
        } catch {
            return false
        }
    }
}
