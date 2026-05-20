import Foundation
import GraphCore

/// v1.0-alpha.8 — One commit on GitHub. SHA stays full so the UI can
/// render a 7-char prefix and the on-disk cache can detect a no-op
/// refresh.
public struct GitHubCommit: Sendable, Codable, Identifiable, Hashable {
    public var id: String { sha }
    public let sha: String
    public let message: String
    public let authorName: String
    public let authorEmail: String
    public let committedAt: Date
    public let url: String

    public init(
        sha: String,
        message: String,
        authorName: String,
        authorEmail: String,
        committedAt: Date,
        url: String
    ) {
        self.sha = sha
        self.message = message
        self.authorName = authorName
        self.authorEmail = authorEmail
        self.committedAt = committedAt
        self.url = url
    }
}

/// v1.0-alpha.8 — Roll-up stats per repo. `lastPushedAt` is the
/// repo-level `pushed_at` from the GitHub API, *not* the latest
/// commit timestamp — they differ when a branch other than `main`
/// gets force-pushed.
public struct GitHubRepoStats: Sendable, Codable, Hashable {
    public let stars: Int
    public let openIssues: Int
    public let defaultBranch: String
    public let lastPushedAt: Date

    public init(
        stars: Int,
        openIssues: Int,
        defaultBranch: String,
        lastPushedAt: Date
    ) {
        self.stars = stars
        self.openIssues = openIssues
        self.defaultBranch = defaultBranch
        self.lastPushedAt = lastPushedAt
    }
}

/// v1.0-alpha.8 — One open GitHub Issue. The UI never renders these
/// today but the value type ships so a follow-up wave can light up a
/// "Open issues" card without a model change.
public struct GitHubIssue: Sendable, Codable, Identifiable, Hashable {
    public let id: Int
    public let number: Int
    public let title: String
    public let state: String         // "open" / "closed"
    public let labels: [String]
    public let updatedAt: Date
    public let url: String

    public init(
        id: Int,
        number: Int,
        title: String,
        state: String,
        labels: [String],
        updatedAt: Date,
        url: String
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.state = state
        self.labels = labels
        self.updatedAt = updatedAt
        self.url = url
    }
}

/// v1.0-alpha.8 — Failure modes the UI cares about. Mirrors
/// `VercelClientError` for cross-provider symmetry in the call sites.
public enum GitHubClientError: Error, Sendable, Equatable {
    case noToken
    case http(Int)
    case decode
    case network(String)

    public static func == (lhs: GitHubClientError, rhs: GitHubClientError) -> Bool {
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

/// v1.0-alpha.8 — Actor that owns every outbound GitHub API call.
/// Reads its bearer token lazily on every request so a just-saved
/// token is picked up immediately.
public actor GitHubClient {
    public static let shared = GitHubClient()

    static let baseURL: URL = URL(string: "https://api.github.com")!
    static let acceptHeader: String = "application/vnd.github+json"
    static let apiVersionHeader: String = "2022-11-28"

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Public API

    /// `GET /repos/<repo>/commits?per_page=N`. Returns the N most
    /// recent commits on the default branch.
    public func recentCommits(repo: String, limit: Int = 5) async throws -> [GitHubCommit] {
        let token = try requireToken()
        guard let url = Self.commitsURL(repo: repo, limit: limit) else {
            throw GitHubClientError.decode
        }
        let request = signedRequest(url: url, token: token)
        let (data, response) = try await perform(request: request)
        guard (200..<300).contains(response) else {
            throw GitHubClientError.http(response)
        }
        do {
            let dtos = try JSONDecoder().decode([GitHubCommitDTO].self, from: data)
            return dtos.map { $0.commitValue }
        } catch {
            throw GitHubClientError.decode
        }
    }

    /// `GET /repos/<repo>`. Returns the stars / open-issues / default
    /// branch / last-pushed snapshot rendered as the repo header.
    public func repoStats(repo: String) async throws -> GitHubRepoStats {
        let token = try requireToken()
        guard let url = Self.repoURL(repo: repo) else {
            throw GitHubClientError.decode
        }
        let request = signedRequest(url: url, token: token)
        let (data, response) = try await perform(request: request)
        guard (200..<300).contains(response) else {
            throw GitHubClientError.http(response)
        }
        do {
            let dto = try JSONDecoder().decode(GitHubRepoDTO.self, from: data)
            return dto.stats
        } catch {
            throw GitHubClientError.decode
        }
    }

    /// `GET /repos/<repo>/issues?state=open&per_page=N`. Returns up to
    /// N open issues; the GitHub `issues` endpoint includes pull
    /// requests (issue-shaped), which the filter below removes.
    public func openIssues(repo: String, limit: Int = 5) async throws -> [GitHubIssue] {
        let token = try requireToken()
        guard let url = Self.issuesURL(repo: repo, limit: limit) else {
            throw GitHubClientError.decode
        }
        let request = signedRequest(url: url, token: token)
        let (data, response) = try await perform(request: request)
        guard (200..<300).contains(response) else {
            throw GitHubClientError.http(response)
        }
        do {
            let dtos = try JSONDecoder().decode([GitHubIssueDTO].self, from: data)
            return dtos.compactMap { $0.issue }
        } catch {
            throw GitHubClientError.decode
        }
    }

    /// v1.0-alpha.10 — `GET /repos/<repo>/contents/<path>` returning
    /// the decoded UTF-8 string body of the file, or nil when the
    /// file doesn't exist (404), the contents are non-text, or the
    /// upstream returns any other error. Soft-fail by design — the
    /// `RepositoryAuditProbe` probes a fixed set of optional files
    /// (package.json, tsconfig.json, etc.) and a missing one is
    /// information, not an error.
    public func readFile(repo: String, path: String) async -> String? {
        guard let token = GitHubTokenStore.read(), !token.isEmpty else {
            return nil
        }
        guard let url = Self.contentsURL(repo: repo, path: path) else {
            return nil
        }
        let request = signedRequest(url: url, token: token)
        do {
            let (data, status) = try await perform(request: request)
            guard (200..<300).contains(status) else { return nil }
            let dto = try JSONDecoder().decode(GitHubContentsDTO.self, from: data)
            guard let encoded = dto.content, dto.encoding == "base64" else {
                return nil
            }
            let cleaned = encoded.replacingOccurrences(of: "\n", with: "")
            guard let raw = Data(base64Encoded: cleaned) else { return nil }
            return String(data: raw, encoding: .utf8)
        } catch {
            return nil
        }
    }

    /// v1.0-alpha.10 — `GET /repos/<repo>/contents/<path>` returning a
    /// shallow listing of the directory at `path`. Each entry carries
    /// its name and type (`"file"` / `"dir"`). Returns an empty array
    /// when the directory is missing or the upstream errors — soft-
    /// fail aligned with `readFile(repo:path:)`.
    public func listDirectory(repo: String, path: String) async -> [GitHubContentEntry] {
        guard let token = GitHubTokenStore.read(), !token.isEmpty else {
            return []
        }
        guard let url = Self.contentsURL(repo: repo, path: path) else {
            return []
        }
        let request = signedRequest(url: url, token: token)
        do {
            let (data, status) = try await perform(request: request)
            guard (200..<300).contains(status) else { return [] }
            let entries = try JSONDecoder().decode([GitHubContentEntry].self, from: data)
            return entries
        } catch {
            return []
        }
    }

    /// v1.0-alpha.10 — `GET /repos/<repo>/git/trees/<branch>?recursive=1`
    /// — full-repo listing used to surface `.env*` and `*.test.*`
    /// files cheaply (one call instead of one per directory). Returns
    /// an empty array on any error.
    public func recursiveTree(repo: String, branch: String = "main") async -> [GitHubTreeEntry] {
        guard let token = GitHubTokenStore.read(), !token.isEmpty else {
            return []
        }
        guard let url = Self.treeURL(repo: repo, branch: branch) else {
            return []
        }
        let request = signedRequest(url: url, token: token)
        do {
            let (data, status) = try await perform(request: request)
            guard (200..<300).contains(status) else { return [] }
            let dto = try JSONDecoder().decode(GitHubTreeDTO.self, from: data)
            return dto.tree ?? []
        } catch {
            return []
        }
    }

    /// Lightweight token validation — calls `GET /user` and checks
    /// for 200. Used by the Settings "Test connexion" button.
    public func validateToken() async -> Bool {
        guard let token = GitHubTokenStore.read(), !token.isEmpty else {
            return false
        }
        let url = Self.baseURL.appendingPathComponent("user")
        let request = signedRequest(url: url, token: token)
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return http.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - URL builders (pure helpers exposed for tests)

    /// `GET /repos/<repo>/commits?per_page=N`
    public static func commitsURL(repo: String, limit: Int) -> URL? {
        guard !repo.isEmpty else { return nil }
        var components = URLComponents(url: baseURL.appendingPathComponent("repos/\(repo)/commits"),
                                       resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "per_page", value: "\(limit)")]
        return components?.url
    }

    /// `GET /repos/<repo>`
    public static func repoURL(repo: String) -> URL? {
        guard !repo.isEmpty else { return nil }
        return baseURL.appendingPathComponent("repos/\(repo)")
    }

    /// `GET /repos/<repo>/issues?state=open&per_page=N`
    public static func issuesURL(repo: String, limit: Int) -> URL? {
        guard !repo.isEmpty else { return nil }
        var components = URLComponents(url: baseURL.appendingPathComponent("repos/\(repo)/issues"),
                                       resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "state", value: "open"),
            URLQueryItem(name: "per_page", value: "\(limit)"),
        ]
        return components?.url
    }

    /// v1.0-alpha.10 — `GET /repos/<repo>/contents/<path>` URL builder.
    /// Returns nil for empty repo. Path components are percent-encoded
    /// so file names with spaces / scoped segments survive the call.
    public static func contentsURL(repo: String, path: String) -> URL? {
        guard !repo.isEmpty else { return nil }
        let trimmedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let suffix = trimmedPath.isEmpty ? "" : "/\(trimmedPath)"
        let allowed = CharacterSet.urlPathAllowed
        // Keep `/` in path so nested directories still resolve.
        let encoded = suffix
            .addingPercentEncoding(withAllowedCharacters: allowed) ?? suffix
        return URL(string: "https://api.github.com/repos/\(repo)/contents\(encoded)")
    }

    /// v1.0-alpha.10 — `GET /repos/<repo>/git/trees/<branch>?recursive=1`
    /// URL builder. Returns nil for empty repo. Branch defaults to
    /// `main`; the probe falls back to `master` on a 404.
    public static func treeURL(repo: String, branch: String) -> URL? {
        guard !repo.isEmpty else { return nil }
        let trimmedBranch = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        let ref = trimmedBranch.isEmpty ? "main" : trimmedBranch
        var components = URLComponents(
            url: baseURL.appendingPathComponent("repos/\(repo)/git/trees/\(ref)"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "recursive", value: "1")]
        return components?.url
    }

    // MARK: - Internals

    private func requireToken() throws -> String {
        guard let token = GitHubTokenStore.read(), !token.isEmpty else {
            throw GitHubClientError.noToken
        }
        return token
    }

    private func signedRequest(url: URL, token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.acceptHeader, forHTTPHeaderField: "Accept")
        request.setValue(Self.apiVersionHeader, forHTTPHeaderField: "X-GitHub-Api-Version")
        request.timeoutInterval = 15
        return request
    }

    private func perform(request: URLRequest) async throws -> (Data, Int) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw GitHubClientError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw GitHubClientError.decode
        }
        return (data, http.statusCode)
    }
}

// MARK: - Wire format

/// `/repos/<repo>/commits` wire shape — we project the slim subset
/// the UI actually reads, soft-defaulting absent fields.
private struct GitHubCommitDTO: Decodable {
    let sha: String
    let html_url: String?
    let commit: CommitDetails

    struct CommitDetails: Decodable {
        let message: String
        let author: AuthorDetails?
    }
    struct AuthorDetails: Decodable {
        let name: String?
        let email: String?
        let date: Date?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.name = try c.decodeIfPresent(String.self, forKey: .name)
            self.email = try c.decodeIfPresent(String.self, forKey: .email)
            if let raw = try c.decodeIfPresent(String.self, forKey: .date) {
                let formatter = ISO8601DateFormatter()
                self.date = formatter.date(from: raw)
            } else {
                self.date = nil
            }
        }

        enum CodingKeys: String, CodingKey {
            case name, email, date
        }
    }

    var commitValue: GitHubCommit {
        let messageLine = self.commit.message
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map(String.init) ?? self.commit.message
        return GitHubCommit(
            sha: sha,
            message: messageLine,
            authorName: self.commit.author?.name ?? "",
            authorEmail: self.commit.author?.email ?? "",
            committedAt: self.commit.author?.date ?? Date(timeIntervalSince1970: 0),
            url: html_url ?? ""
        )
    }
}

/// `/repos/<repo>` wire shape.
private struct GitHubRepoDTO: Decodable {
    let stargazers_count: Int?
    let open_issues_count: Int?
    let default_branch: String?
    let pushed_at: String?

    var stats: GitHubRepoStats {
        let date: Date
        if let raw = pushed_at {
            date = ISO8601DateFormatter().date(from: raw) ?? Date(timeIntervalSince1970: 0)
        } else {
            date = Date(timeIntervalSince1970: 0)
        }
        return GitHubRepoStats(
            stars: stargazers_count ?? 0,
            openIssues: open_issues_count ?? 0,
            defaultBranch: default_branch ?? "main",
            lastPushedAt: date
        )
    }
}

// MARK: - v1.0-alpha.10 — Contents / Tree wire shapes

/// One shallow entry returned by `GET /repos/<repo>/contents/<path>`
/// when the target is a directory. Used by `RepositoryAuditProbe` to
/// classify `.github/workflows/*.yml` and similar shallow listings.
public struct GitHubContentEntry: Sendable, Codable, Equatable {
    public let name: String
    public let path: String
    public let type: String  // "file" | "dir" | "symlink" | "submodule"
    public let size: Int?

    public init(name: String, path: String, type: String, size: Int? = nil) {
        self.name = name
        self.path = path
        self.type = type
        self.size = size
    }
}

/// One entry in the recursive git tree (`/git/trees/<ref>?recursive=1`).
/// `path` is the full repo-relative path with forward slashes; `type`
/// is `"blob"` for files and `"tree"` for directories.
public struct GitHubTreeEntry: Sendable, Codable, Equatable {
    public let path: String
    public let type: String
    public let size: Int?

    public init(path: String, type: String, size: Int? = nil) {
        self.path = path
        self.type = type
        self.size = size
    }
}

/// `/contents/<file>` wire shape. We project `content` + `encoding`
/// (typically `"base64"`); the probe handles the decode.
private struct GitHubContentsDTO: Decodable {
    let content: String?
    let encoding: String?
}

/// `/git/trees/<ref>` wire shape. The recursive flag flattens the
/// tree; `truncated == true` means the call hit GitHub's per-call
/// cap (rare for cockpit-scale repos but the probe doesn't care —
/// it just reads what came back).
private struct GitHubTreeDTO: Decodable {
    let tree: [GitHubTreeEntry]?
    let truncated: Bool?
}

/// `/repos/<repo>/issues` wire shape. GitHub mixes PRs into this
/// payload — we drop entries where `pull_request` is present.
private struct GitHubIssueDTO: Decodable {
    let id: Int?
    let number: Int?
    let title: String?
    let state: String?
    let html_url: String?
    let updated_at: String?
    let labels: [LabelDTO]?
    let pull_request: PullRequestStub?

    struct LabelDTO: Decodable {
        let name: String?
    }

    struct PullRequestStub: Decodable {}

    var issue: GitHubIssue? {
        if pull_request != nil { return nil }
        guard let id, let number, let title, let state else { return nil }
        let labelNames = (labels ?? []).compactMap { $0.name }
        let date: Date
        if let raw = updated_at {
            date = ISO8601DateFormatter().date(from: raw) ?? Date(timeIntervalSince1970: 0)
        } else {
            date = Date(timeIntervalSince1970: 0)
        }
        return GitHubIssue(
            id: id,
            number: number,
            title: title,
            state: state,
            labels: labelNames,
            updatedAt: date,
            url: html_url ?? ""
        )
    }
}
