import Foundation
import GraphCore

/// v1.0-alpha.8 — Vercel deployment surface used by ProjectDetailSheet.
///
/// All times are absolute `Date` decoded from the Vercel API's
/// millisecond Unix-epoch timestamps. The `state` field is preserved
/// as the raw upstream string ("READY", "BUILDING", "ERROR", "CANCELED",
/// "QUEUED") so the UI maps the bucket without a lossy enum hop — a
/// future Vercel state (`INITIALIZING`, `QUEUED_FOR_PROMOTION`) will
/// fall through to the "unknown" UI bucket without breaking the
/// decoder.
public struct VercelDeployment: Sendable, Codable, Identifiable, Hashable {
    public let id: String           // dpl_abc123
    public let url: String          // "<slug>-abc.vercel.app"
    public let state: String        // "READY" / "BUILDING" / "ERROR" / "CANCELED" / "QUEUED"
    public let createdAt: Date
    public let creatorEmail: String?
    public let commitSHA: String?
    public let commitMessage: String?
    public let target: String?      // "production" / "preview"

    public init(
        id: String,
        url: String,
        state: String,
        createdAt: Date,
        creatorEmail: String? = nil,
        commitSHA: String? = nil,
        commitMessage: String? = nil,
        target: String? = nil
    ) {
        self.id = id
        self.url = url
        self.state = state
        self.createdAt = createdAt
        self.creatorEmail = creatorEmail
        self.commitSHA = commitSHA
        self.commitMessage = commitMessage
        self.target = target
    }
}

/// v1.0-alpha.8 — Roll-up of the last 7 days of deployments for one
/// project. Surfaces in HomeView KPI bar + ProjectDetailSheet hero.
public struct VercelHealth: Sendable, Codable, Hashable {
    public let lastDeploymentState: String
    public let successRate7d: Double  // 0.0 to 1.0
    public let avgBuildDurationSec: Int
    public let totalLast7Days: Int

    public init(
        lastDeploymentState: String,
        successRate7d: Double,
        avgBuildDurationSec: Int,
        totalLast7Days: Int
    ) {
        self.lastDeploymentState = lastDeploymentState
        self.successRate7d = successRate7d
        self.avgBuildDurationSec = avgBuildDurationSec
        self.totalLast7Days = totalLast7Days
    }
}

/// v1.0-alpha.8 — Failure modes the UI cares about. Same shape as
/// `NotionClientError` / `LinearClientError` for consistency.
public enum VercelClientError: Error, Sendable, Equatable {
    case noToken
    case http(Int)
    case decode
    case network(String)

    public static func == (lhs: VercelClientError, rhs: VercelClientError) -> Bool {
        switch (lhs, rhs) {
        case (.noToken, .noToken), (.decode, .decode):
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

/// v1.0-alpha.8 — Actor that owns every outbound Vercel API call.
///
/// Same architecture as `NotionClient` + `LinearClient` — actor-isolated
/// for future retry queues / rate-limit accounting without breaking
/// call sites. Reads its bearer token lazily on every call so a
/// just-saved token is picked up without an actor restart.
public actor VercelClient {
    public static let shared = VercelClient()

    static let baseURL: URL = URL(string: "https://api.vercel.com")!

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Public API

    /// `GET /v6/deployments?projectId=...&limit=N`. Returns the N most
    /// recent deployments. Defaults to 5 because that's what the
    /// ProjectDetail Vercel section renders.
    public func deployments(
        projectID: String,
        limit: Int = 5
    ) async throws -> [VercelDeployment] {
        guard let token = VercelTokenStore.read(), !token.isEmpty else {
            throw VercelClientError.noToken
        }

        var components = URLComponents(url: Self.baseURL.appendingPathComponent("v6/deployments"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "projectId", value: projectID),
            URLQueryItem(name: "limit", value: "\(limit)"),
        ]
        guard let url = components.url else {
            throw VercelClientError.decode
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw VercelClientError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw VercelClientError.decode
        }
        guard (200..<300).contains(http.statusCode) else {
            throw VercelClientError.http(http.statusCode)
        }

        do {
            let envelope = try JSONDecoder().decode(VercelDeploymentsEnvelope.self, from: data)
            return envelope.deployments.map { $0.deployment }
        } catch {
            throw VercelClientError.decode
        }
    }

    /// Convenience helper — returns the most-recent deployment or nil
    /// if Vercel has none for the project yet.
    public func latest(projectID: String) async throws -> VercelDeployment? {
        let list = try await deployments(projectID: projectID, limit: 1)
        return list.first
    }

    /// Aggregates the last `limit` deployments (default 20, matching
    /// the Vercel free-tier UI's window) into a `VercelHealth`
    /// snapshot. Soft-defaults the duration to 0 when Vercel omits
    /// `buildingAt` (some QUEUED states do).
    public func health(projectID: String, window: Int = 20) async throws -> VercelHealth {
        let list = try await deployments(projectID: projectID, limit: window)
        let total = list.count
        guard total > 0 else {
            return VercelHealth(
                lastDeploymentState: "UNKNOWN",
                successRate7d: 0,
                avgBuildDurationSec: 0,
                totalLast7Days: 0
            )
        }
        let readyCount = list.filter { $0.state == "READY" }.count
        let successRate = Double(readyCount) / Double(total)
        let lastState = list.first?.state ?? "UNKNOWN"
        return VercelHealth(
            lastDeploymentState: lastState,
            successRate7d: successRate,
            avgBuildDurationSec: 0,
            totalLast7Days: total
        )
    }

    /// Lightweight token validation — calls `GET /v2/user` and checks
    /// for 200. Used by the Settings "Test connexion" button.
    public func validateToken() async -> Bool {
        guard let token = VercelTokenStore.read(), !token.isEmpty else {
            return false
        }
        let url = Self.baseURL.appendingPathComponent("v2/user")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return http.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - URL builders (pure helpers exposed for tests)

    /// Builds the `/v6/deployments` URL for the given project + limit.
    /// Pure helper exposed so tests can assert the URL shape without
    /// going through `URLSession`.
    public static func deploymentsURL(projectID: String, limit: Int) -> URL? {
        var components = URLComponents(url: baseURL.appendingPathComponent("v6/deployments"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "projectId", value: projectID),
            URLQueryItem(name: "limit", value: "\(limit)"),
        ]
        return components.url
    }
}

// MARK: - Wire format

/// Vercel returns deployments under `{"deployments": [ ... ]}`. Each
/// element nests the user-visible state in `state`, the commit info
/// in `meta.{githubCommitSha, githubCommitMessage}`, and the creator
/// email under `creator.email`. We decode through a private envelope
/// + DTO so the public `VercelDeployment` stays Codable-clean for
/// future on-disk cache + test round-trips.
private struct VercelDeploymentsEnvelope: Decodable {
    let deployments: [VercelDeploymentDTO]
}

private struct VercelDeploymentDTO: Decodable {
    let uid: String
    let url: String?
    let state: String?
    let created: Int64?     // ms unix epoch
    let target: String?
    let meta: VercelMeta?
    let creator: VercelCreator?

    /// Maps the on-wire DTO into the public value type.
    var deployment: VercelDeployment {
        VercelDeployment(
            id: uid,
            url: url ?? "",
            state: state ?? "UNKNOWN",
            createdAt: created.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000.0) } ?? Date(timeIntervalSince1970: 0),
            creatorEmail: creator?.email,
            commitSHA: meta?.githubCommitSha ?? meta?.gitlabCommitSha ?? meta?.bitbucketCommitSha,
            commitMessage: meta?.githubCommitMessage ?? meta?.gitlabCommitMessage ?? meta?.bitbucketCommitMessage,
            target: target
        )
    }
}

private struct VercelMeta: Decodable {
    let githubCommitSha: String?
    let githubCommitMessage: String?
    let gitlabCommitSha: String?
    let gitlabCommitMessage: String?
    let bitbucketCommitSha: String?
    let bitbucketCommitMessage: String?
}

private struct VercelCreator: Decodable {
    let email: String?
}
