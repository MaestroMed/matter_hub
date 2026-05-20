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

    // MARK: - v1.2.0 — Bidirectional sync (Notion → MIND)

    /// `POST /v1/search` with a filter restricted to `object: "database"`.
    /// Returns every database the integration has been shared with.
    /// Sorts by `last_edited_time` descending so the wizard surfaces
    /// the most-recently-touched databases first.
    public func listDatabases() async throws -> [NotionDatabase] {
        guard let token = NotionTokenStore.read(), !token.isEmpty else {
            throw NotionClientError.noToken
        }
        let url = Self.baseURL.appendingPathComponent("v1/search")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "filter": ["value": "database", "property": "object"],
            "sort": ["direction": "descending", "timestamp": "last_edited_time"],
            "page_size": 100,
        ]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            throw NotionClientError.decoding
        }

        let data = try await execute(request)
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let results = json["results"] as? [[String: Any]]
        else {
            throw NotionClientError.decoding
        }
        return results.compactMap(NotionClient.decodeDatabase(from:))
    }

    /// `POST /v1/databases/<id>/query` returning at most `pageSize`
    /// pages on a single request. The optional filter narrows the
    /// row set when the wizard wants only a slice (e.g. "Status =
    /// Active"). Pagination is intentionally not exposed — v1.2.0
    /// caps every import at 100 rows.
    public func queryDatabase(
        _ databaseID: String,
        filter: NotionDatabaseFilter? = nil,
        pageSize: Int = 100
    ) async throws -> [NotionPage] {
        guard let token = NotionTokenStore.read(), !token.isEmpty else {
            throw NotionClientError.noToken
        }
        let url = Self.baseURL.appendingPathComponent("v1/databases/\(databaseID)/query")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "page_size": max(1, min(100, pageSize)),
        ]
        if let filter {
            body["filter"] = NotionClient.encodeFilter(filter)
        }
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            throw NotionClientError.decoding
        }

        let data = try await execute(request)
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let results = json["results"] as? [[String: Any]]
        else {
            throw NotionClientError.decoding
        }
        return results.compactMap { NotionClient.decodePage(from: $0, parentDatabaseID: databaseID) }
    }

    /// `GET /v1/pages/<id>`. Used by the foreground bidirectional
    /// tick to refresh a single page when its `lastEditedAt` has
    /// drifted past `lastNotionSyncAt`.
    public func retrievePage(_ pageID: String) async throws -> NotionPage {
        guard let token = NotionTokenStore.read(), !token.isEmpty else {
            throw NotionClientError.noToken
        }
        let url = Self.baseURL.appendingPathComponent("v1/pages/\(pageID)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "Notion-Version")

        let data = try await execute(request)
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let page = NotionClient.decodePage(from: json, parentDatabaseID: nil)
        else {
            throw NotionClientError.decoding
        }
        return page
    }

    /// `GET /v1/blocks/<id>/children`. Returns the immediate-child
    /// blocks of a page; nested children are not auto-recursed in
    /// v1.2.0. `depth` on `NotionBlock` is reserved for v1.3 nested-
    /// list rendering.
    public func pageBlocks(_ pageID: String) async throws -> [NotionBlock] {
        guard let token = NotionTokenStore.read(), !token.isEmpty else {
            throw NotionClientError.noToken
        }
        let url = Self.baseURL.appendingPathComponent("v1/blocks/\(pageID)/children")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "Notion-Version")

        let data = try await execute(request)
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let results = json["results"] as? [[String: Any]]
        else {
            throw NotionClientError.decoding
        }
        return results.compactMap(NotionClient.decodeBlock(from:))
    }

    // MARK: - Internal HTTP plumbing

    /// 2xx-or-throw helper — every new bidirectional GET + POST
    /// routes through here so the 401 / 5xx / transport handling
    /// stays in one place.
    private func execute(_ request: URLRequest) async throws -> Data {
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
            return data
        case 401:
            throw NotionClientError.invalidToken
        default:
            throw NotionClientError.http(http.statusCode)
        }
    }
}

// MARK: - Notion JSON decoders
//
// These statics are exposed `internal` (default) so the test target
// can unit-test the flattening without spinning up a fake network
// session. JSON shapes taken from the Notion 2022-06-28 reference.

extension NotionClient {

    /// Lifts a `database` object from `/v1/search` into our value
    /// type. Soft-fails on missing required fields (returns nil so
    /// `.compactMap` drops malformed rows).
    static func decodeDatabase(from json: [String: Any]) -> NotionDatabase? {
        guard
            let id = json["id"] as? String,
            let editedAtString = json["last_edited_time"] as? String,
            let editedAt = parseNotionDate(editedAtString)
        else { return nil }
        let title = flattenRichText(json["title"] as? [[String: Any]])
        let icon = decodeIcon(json["icon"] as? [String: Any])
        let propertyNames: [String]
        if let properties = json["properties"] as? [String: Any] {
            propertyNames = properties.keys.sorted()
        } else {
            propertyNames = []
        }
        return NotionDatabase(
            id: id,
            title: title.isEmpty ? "Sans titre" : title,
            icon: icon,
            lastEditedAt: editedAt,
            propertyNames: propertyNames
        )
    }

    /// Lifts a page object into our value type. Walks every cell
    /// type and flattens it into a plain String so the planner /
    /// executor see a clean `[String: String]`.
    static func decodePage(from json: [String: Any], parentDatabaseID: String?) -> NotionPage? {
        guard
            let id = json["id"] as? String,
            let createdAtString = json["created_time"] as? String,
            let editedAtString = json["last_edited_time"] as? String,
            let createdAt = parseNotionDate(createdAtString),
            let editedAt = parseNotionDate(editedAtString)
        else { return nil }
        let url = json["url"] as? String ?? ""
        let icon = decodeIcon(json["icon"] as? [String: Any])
        let parsedParentDB: String?
        if let parent = json["parent"] as? [String: Any],
           let dbID = parent["database_id"] as? String {
            parsedParentDB = dbID
        } else {
            parsedParentDB = parentDatabaseID
        }
        var flat: [String: String] = [:]
        var titleFromProperties = ""
        if let properties = json["properties"] as? [String: Any] {
            for (key, raw) in properties {
                guard let cell = raw as? [String: Any] else { continue }
                let (value, isTitle) = flattenCell(cell)
                flat[key] = value
                if isTitle, !value.isEmpty {
                    titleFromProperties = value
                }
            }
        }
        return NotionPage(
            id: id,
            title: titleFromProperties.isEmpty ? "Sans titre" : titleFromProperties,
            icon: icon,
            createdAt: createdAt,
            lastEditedAt: editedAt,
            properties: flat,
            url: url,
            parentDatabaseID: parsedParentDB
        )
    }

    /// Lifts one block child. Polymorphic — `type` discriminator
    /// points at a sibling key that holds the rich-text array.
    static func decodeBlock(from json: [String: Any]) -> NotionBlock? {
        guard
            let id = json["id"] as? String,
            let type = json["type"] as? String
        else { return nil }
        let body = json[type] as? [String: Any]
        let rich = body?["rich_text"] as? [[String: Any]]
        let text = flattenRichText(rich)
        return NotionBlock(id: id, type: type, plainText: text, depth: 0)
    }

    /// Single-source-of-truth filter encoder. Encodes `rich_text`
    /// filters — they work against text + title columns alike.
    static func encodeFilter(_ filter: NotionDatabaseFilter) -> [String: Any] {
        let comparator = filter.comparator.lowercased() == "contains" ? "contains" : "equals"
        return [
            "property": filter.property,
            "rich_text": [comparator: filter.value],
        ]
    }

    /// Walks one property cell variant and returns `(value, isTitle)`.
    /// Every supported Notion property type folds down to a String;
    /// unsupported types return "".
    static func flattenCell(_ cell: [String: Any]) -> (String, Bool) {
        guard let type = cell["type"] as? String else { return ("", false) }
        switch type {
        case "title":
            return (flattenRichText(cell["title"] as? [[String: Any]]), true)
        case "rich_text":
            return (flattenRichText(cell["rich_text"] as? [[String: Any]]), false)
        case "number":
            if let n = cell["number"] as? Double {
                let asInt = Int(exactly: n)
                return (asInt.map(String.init) ?? String(n), false)
            }
            return ("", false)
        case "select":
            if let select = cell["select"] as? [String: Any],
               let name = select["name"] as? String { return (name, false) }
            return ("", false)
        case "status":
            if let status = cell["status"] as? [String: Any],
               let name = status["name"] as? String { return (name, false) }
            return ("", false)
        case "multi_select":
            if let arr = cell["multi_select"] as? [[String: Any]] {
                return (arr.compactMap { $0["name"] as? String }.joined(separator: ", "), false)
            }
            return ("", false)
        case "date":
            if let date = cell["date"] as? [String: Any],
               let start = date["start"] as? String { return (start, false) }
            return ("", false)
        case "checkbox":
            return ((cell["checkbox"] as? Bool == true) ? "true" : "false", false)
        case "url":
            return ((cell["url"] as? String) ?? "", false)
        case "email":
            return ((cell["email"] as? String) ?? "", false)
        case "phone_number":
            return ((cell["phone_number"] as? String) ?? "", false)
        case "people":
            if let arr = cell["people"] as? [[String: Any]] {
                return (arr.compactMap { $0["name"] as? String }.joined(separator: ", "), false)
            }
            return ("", false)
        default:
            return ("", false)
        }
    }

    /// Folds rich-text spans into the concatenated plain string.
    static func flattenRichText(_ spans: [[String: Any]]?) -> String {
        guard let spans else { return "" }
        return spans.compactMap { $0["plain_text"] as? String }.joined()
    }

    /// Decodes the icon block — emoji vs file URL.
    static func decodeIcon(_ icon: [String: Any]?) -> String? {
        guard let icon else { return nil }
        if let type = icon["type"] as? String {
            switch type {
            case "emoji":
                return icon["emoji"] as? String
            case "external":
                if let external = icon["external"] as? [String: Any] {
                    return external["url"] as? String
                }
            case "file":
                if let file = icon["file"] as? [String: Any] {
                    return file["url"] as? String
                }
            default:
                return nil
            }
        }
        return nil
    }

    /// Notion timestamps are ISO 8601 with millisecond precision and
    /// a `Z` zone. Toggle `withFractionalSeconds`, fall back to plain.
    static func parseNotionDate(_ raw: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }
}
