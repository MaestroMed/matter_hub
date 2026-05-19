import Foundation
import AuditKit
import GraphCore

/// Errors surfaced by `LinearClient`. Cases map 1-to-1 onto the
/// failure modes the UI cares about — the Settings "Save token" button
/// and the AuditSheet "Push to Linear" / "Export all QW" buttons both
/// render the case as a short toast.
public enum LinearClientError: Error, Sendable, Equatable {
    /// `LinearTokenStore.read()` returned nil — the user hasn't pasted
    /// a personal API key yet.
    case noToken

    /// The Linear API returned 401 — token rejected. Either the key is
    /// malformed or has been revoked from linear.app/settings/api.
    case invalidToken

    /// Any other non-2xx HTTP response. The status code is preserved
    /// so the UI can surface it in error toasts.
    case http(Int)

    /// GraphQL-level failure: the HTTP transport succeeded but the
    /// response payload contained an `errors` array (or the
    /// mutation's `success` field came back as false). The string
    /// holds the first error message for the toast.
    case graphQL(String)

    /// JSONSerialization or response decoding failed.
    case decoding

    /// URLSession-level transport failure (offline, TLS error, etc.).
    case transport(String)

    public static func == (lhs: LinearClientError, rhs: LinearClientError) -> Bool {
        switch (lhs, rhs) {
        case (.noToken, .noToken), (.invalidToken, .invalidToken), (.decoding, .decoding):
            return true
        case let (.http(a), .http(b)):
            return a == b
        case let (.graphQL(a), .graphQL(b)):
            return a == b
        case let (.transport(a), .transport(b)):
            return a == b
        default:
            return false
        }
    }
}

/// Result of a bulk push. Captures partial failures so the AuditSheet
/// can surface "3/5 succeeded" rather than failing the whole batch on
/// the first hiccup. Sendable so it can cross the actor boundary back
/// to the @MainActor UI without an explicit hop.
public struct LinearBulkResult: Sendable, Equatable {
    /// Linear issue identifiers (e.g. `ENG-128`) for QuickWins that
    /// landed. Empty array = nothing landed.
    public let createdIdentifiers: [String]

    /// (QuickWin index, error) tuples for each row that failed. Indexes
    /// match the input array's order so the UI can highlight which
    /// rows didn't make it.
    public let failures: [(index: Int, error: String)]

    public init(createdIdentifiers: [String], failures: [(index: Int, error: String)]) {
        self.createdIdentifiers = createdIdentifiers
        self.failures = failures
    }

    public static func == (lhs: LinearBulkResult, rhs: LinearBulkResult) -> Bool {
        guard lhs.createdIdentifiers == rhs.createdIdentifiers else { return false }
        guard lhs.failures.count == rhs.failures.count else { return false }
        for (a, b) in zip(lhs.failures, rhs.failures) where a.index != b.index || a.error != b.error {
            return false
        }
        return true
    }
}

/// Actor that owns every outbound Linear GraphQL call.
///
/// Why an actor?
/// -------------
/// The client holds no mutable state today beyond its `URLSession`
/// reference, but keeping it as an actor leaves room for v0.12.x
/// retry queues, rate-limit accounting, and the eventual OAuth swap
/// without breaking call sites. Every call site already awaits the
/// methods, so the boundary stays clean.
public actor LinearClient {
    /// Shared instance used by Settings + AuditSheet. The UI never
    /// constructs its own — keeping a single instance means a future
    /// retry queue / rate-limit bucket can live on the actor without
    /// duplicating state.
    public static let shared = LinearClient()

    static let endpoint: URL = URL(string: "https://api.linear.app/graphql")!

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Public API

    /// POSTs a single `issueCreate` mutation for one QuickWin. Returns
    /// the Linear issue identifier (e.g. `ENG-128`) on success so the
    /// UI can surface it in the success toast.
    public func createIssue(
        _ win: AuditReport.QuickWin,
        teamID: String
    ) async throws -> String {
        guard let token = LinearTokenStore.read(), !token.isEmpty else {
            throw LinearClientError.noToken
        }
        let input = LinearIssueBuilder.issueInput(for: win, teamID: teamID)
        let mutation =
        """
        mutation IssueCreate($input: IssueCreateInput!) {
          issueCreate(input: $input) {
            success
            issue { id identifier url }
          }
        }
        """
        let payload: [String: Any] = [
            "query": mutation,
            "variables": ["input": input],
        ]
        let data = try await postGraphQL(payload, token: token)
        return try Self.parseIssueCreate(data)
    }

    /// Sequential bulk push. We do not parallelise because Linear
    /// rate-limits aggressively (~50 rps per workspace) and a typical
    /// audit has 3-8 quick wins — the latency cost is negligible and
    /// the failure surface stays simple.
    public func createIssuesBulk(
        _ wins: [AuditReport.QuickWin],
        teamID: String
    ) async throws -> LinearBulkResult {
        guard let token = LinearTokenStore.read(), !token.isEmpty else {
            throw LinearClientError.noToken
        }
        var createdIdentifiers: [String] = []
        var failures: [(index: Int, error: String)] = []

        for (idx, win) in wins.enumerated() {
            do {
                let identifier = try await createIssueWithToken(win, teamID: teamID, token: token)
                createdIdentifiers.append(identifier)
            } catch {
                failures.append((index: idx, error: String(describing: error)))
            }
        }

        return LinearBulkResult(createdIdentifiers: createdIdentifiers, failures: failures)
    }

    /// GET-style GraphQL `teams { nodes { id key name } }` query.
    /// Returns the list for the Settings team picker. We sort by name
    /// so the picker order matches what the user sees in linear.app.
    public func teams() async throws -> [LinearTeam] {
        guard let token = LinearTokenStore.read(), !token.isEmpty else {
            throw LinearClientError.noToken
        }
        let query =
        """
        query Teams {
          teams { nodes { id key name } }
        }
        """
        let payload: [String: Any] = ["query": query]
        let data = try await postGraphQL(payload, token: token)
        return try Self.parseTeams(data).sorted { $0.name < $1.name }
    }

    /// GraphQL `viewer { id }` query. Returns true on a 200 response
    /// with a viewer node, false on 401 or missing viewer — used by
    /// Settings to surface the green/red dot next to the saved token.
    public func validateToken() async -> Bool {
        guard let token = LinearTokenStore.read(), !token.isEmpty else {
            return false
        }
        let payload: [String: Any] = ["query": "query Viewer { viewer { id } }"]
        do {
            let data = try await postGraphQL(payload, token: token)
            guard
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let dataDict = json["data"] as? [String: Any],
                let viewer = dataDict["viewer"] as? [String: Any],
                viewer["id"] is String
            else {
                return false
            }
            return true
        } catch {
            return false
        }
    }

    // MARK: - Internals

    /// Inner variant that reuses an already-loaded token. Avoids a
    /// Keychain round-trip on every iteration of the bulk loop.
    private func createIssueWithToken(
        _ win: AuditReport.QuickWin,
        teamID: String,
        token: String
    ) async throws -> String {
        let input = LinearIssueBuilder.issueInput(for: win, teamID: teamID)
        let mutation =
        """
        mutation IssueCreate($input: IssueCreateInput!) {
          issueCreate(input: $input) {
            success
            issue { id identifier url }
          }
        }
        """
        let payload: [String: Any] = [
            "query": mutation,
            "variables": ["input": input],
        ]
        let data = try await postGraphQL(payload, token: token)
        return try Self.parseIssueCreate(data)
    }

    private func postGraphQL(_ payload: [String: Any], token: String) async throws -> Data {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        // Linear's docs: "the value is the API key as-is, without any
        // prefix like 'Bearer '". OAuth tokens DO take the Bearer
        // prefix; the paste-personal-API-key route does not.
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            throw LinearClientError.decoding
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LinearClientError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw LinearClientError.decoding
        }
        switch http.statusCode {
        case 200..<300:
            // Linear always returns 200 even for GraphQL-level errors;
            // we surface them here so the caller doesn't need to
            // double-decode the response.
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errors = json["errors"] as? [[String: Any]],
               let first = errors.first,
               let message = first["message"] as? String {
                throw LinearClientError.graphQL(message)
            }
            return data
        case 401:
            throw LinearClientError.invalidToken
        default:
            throw LinearClientError.http(http.statusCode)
        }
    }

    // MARK: - Response parsing (static so tests can exercise them)

    static func parseIssueCreate(_ data: Data) throws -> String {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let dataDict = json["data"] as? [String: Any],
            let issueCreate = dataDict["issueCreate"] as? [String: Any]
        else {
            throw LinearClientError.decoding
        }
        if let success = issueCreate["success"] as? Bool, !success {
            throw LinearClientError.graphQL("issueCreate returned success=false")
        }
        guard
            let issue = issueCreate["issue"] as? [String: Any],
            let identifier = issue["identifier"] as? String
        else {
            throw LinearClientError.decoding
        }
        return identifier
    }

    static func parseTeams(_ data: Data) throws -> [LinearTeam] {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let dataDict = json["data"] as? [String: Any],
            let teams = dataDict["teams"] as? [String: Any],
            let nodes = teams["nodes"] as? [[String: Any]]
        else {
            throw LinearClientError.decoding
        }
        return nodes.compactMap { node in
            guard
                let id = node["id"] as? String,
                let key = node["key"] as? String,
                let name = node["name"] as? String
            else { return nil }
            return LinearTeam(id: id, key: key, name: name)
        }
    }
}
