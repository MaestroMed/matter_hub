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

/// v1.0-alpha.11 — Bulk Import. Slim repo header projected from
/// `GET /user/repos` (and from `GET /repos/<owner>/<repo>`). Keeps
/// every column the wizard's review step needs to render a row +
/// derive a `RepoMetadata` without pulling the full GitHub payload.
public struct GitHubRepoSummary: Sendable, Codable, Equatable {
    public let fullName: String          // "MaestroMed/AZConstruction_v0"
    public let name: String              // "AZConstruction_v0"
    public let description: String?
    public let isPrivate: Bool
    public let defaultBranch: String
    public let pushedAt: Date
    public let homepageURL: String?
    public let stars: Int
    public let topics: [String]

    public init(
        fullName: String,
        name: String,
        description: String?,
        isPrivate: Bool,
        defaultBranch: String,
        pushedAt: Date,
        homepageURL: String?,
        stars: Int,
        topics: [String]
    ) {
        self.fullName = fullName
        self.name = name
        self.description = description
        self.isPrivate = isPrivate
        self.defaultBranch = defaultBranch
        self.pushedAt = pushedAt
        self.homepageURL = homepageURL
        self.stars = stars
        self.topics = topics
    }
}

/// v1.0-alpha.11 — Bulk Import. Output of `GitHubClient.detectStack`.
/// `framework` is one of `"nextjs" / "wordpress" / "shopify" /
/// "static" / "other"` (string-typed so a future framework can land
/// without forcing every consumer to recompile). `confidence` is a
/// 0…1 self-assessment used by `BulkImportPlanner` to gate the
/// recommended bucket — `< 0.5` defaults to skipped. `signals`
/// surfaces the diagnostic that drove the verdict so a future
/// "why did MIND skip this?" affordance can render them inline.
public struct RepoStackDetection: Sendable, Codable, Equatable {
    public let framework: String
    public let version: String?
    public let confidence: Double
    public let signals: [String]

    public init(
        framework: String,
        version: String?,
        confidence: Double,
        signals: [String]
    ) {
        self.framework = framework
        self.version = version
        self.confidence = confidence
        self.signals = signals
    }
}

/// v1.0-alpha.11 — Bulk Import. Per-repo orchestrator output. Combines
/// the raw `GitHubRepoSummary` + the stack detection + derived
/// columns (slug, name, host, primary color). The wizard renders
/// `RepoMetadata` rows directly; `Project.upsert(from:in:)` writes
/// these fields onto the SwiftData row.
public struct RepoMetadata: Sendable, Codable, Equatable {
    public let suggestedSlug: String     // "az-construction"
    public let suggestedName: String     // "AZ Construction"
    public let suggestedHost: String     // "www.azconstruction.fr" or "<slug>.vercel.app"
    public let suggestedPrimaryColor: String  // default iris if no signal
    public let detection: RepoStackDetection
    public let summary: GitHubRepoSummary

    public init(
        suggestedSlug: String,
        suggestedName: String,
        suggestedHost: String,
        suggestedPrimaryColor: String,
        detection: RepoStackDetection,
        summary: GitHubRepoSummary
    ) {
        self.suggestedSlug = suggestedSlug
        self.suggestedName = suggestedName
        self.suggestedHost = suggestedHost
        self.suggestedPrimaryColor = suggestedPrimaryColor
        self.detection = detection
        self.summary = summary
    }

    /// Default iris tint used when no description / topic signal nudges
    /// the wizard toward a different brand color. Mirrors the
    /// `Project.primaryColor` default so a freshly-imported row
    /// inherits the MIND brand iris.
    public static let defaultPrimaryColor = "#5E5BD8"

    /// Pure derivation of `RepoMetadata` from a `GitHubRepoSummary` +
    /// the matching detection. Tests for each step (slug, name, host,
    /// color) live in `RepoMetadataDerivationTests`.
    public static func derive(
        repo: GitHubRepoSummary,
        detection: RepoStackDetection
    ) -> RepoMetadata {
        let slug = Self.deriveSlug(from: repo.name)
        let name = Self.deriveName(from: repo.name)
        let host = Self.deriveHost(from: repo, slug: slug)
        let color = Self.derivePrimaryColor(from: repo)
        return RepoMetadata(
            suggestedSlug: slug,
            suggestedName: name,
            suggestedHost: host,
            suggestedPrimaryColor: color,
            detection: detection,
            summary: repo
        )
    }

    /// Slug derivation. Strips `_v<digits>` suffix, splits on
    /// CamelCase + underscore boundaries (so `AZConstruction_v0` →
    /// `az-construction` and `IEFandCo_v0` → `ie-fand-co`), then
    /// lowercases and dash-joins. Reuses the same boundary rules
    /// as `deriveName(from:)` so the two columns stay in sync.
    public static func deriveSlug(from repoName: String) -> String {
        // The humanised name already carries word boundaries
        // (`AZ Construction`, `IE Fand Co`); going through it lets
        // slug + name share a single boundary-detection path.
        let humanised = deriveName(from: repoName)
        var output = ""
        var lastWasDash = false
        for scalar in humanised.lowercased().unicodeScalars {
            let ch = Character(scalar)
            if ch.isLetter || ch.isNumber {
                output.append(ch)
                lastWasDash = false
            } else if !lastWasDash && !output.isEmpty {
                output.append("-")
                lastWasDash = true
            }
        }
        while output.hasSuffix("-") { output.removeLast() }
        return output
    }

    /// Human-readable name derived from a CamelCase / `Camel_v0` repo
    /// name. Strips the `_v\d+` suffix then splits on uppercase
    /// boundaries: `AZConstruction` → `AZ Construction`, `IEFandCo`
    /// → `IE Fand Co`. Repos already containing spaces are returned
    /// stripped of the version suffix only.
    public static func deriveName(from repoName: String) -> String {
        var working = repoName
        if let range = working.range(of: "_v[0-9]+$", options: .regularExpression) {
            working.removeSubrange(range)
        }
        // If the input already has spaces, preserve them.
        if working.contains(" ") {
            return working.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Split on uppercase boundaries. Run-of-uppercase stays
        // together until the next uppercase + lowercase pair:
        // `AZConstruction` → `AZ` + `Construction`.
        var output = ""
        let chars = Array(working)
        for (idx, ch) in chars.enumerated() {
            if idx > 0 && ch.isUppercase {
                let prev = chars[idx - 1]
                let next: Character? = idx + 1 < chars.count ? chars[idx + 1] : nil
                let runEnds = prev.isUppercase && (next?.isLowercase ?? false)
                let runStarts = prev.isLowercase || prev.isNumber
                if runStarts || runEnds {
                    output.append(" ")
                }
            }
            output.append(ch)
        }
        return output
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Production host. Prefers the GitHub `homepage` URL when set
    /// (stripping `https?://` + trailing slash). Falls back to
    /// `<slug>.vercel.app` so the cockpit card has a plausible
    /// hostname to render even before Vercel sets one. Empty slug →
    /// empty host.
    public static func deriveHost(from repo: GitHubRepoSummary, slug: String) -> String {
        if let raw = repo.homepageURL?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty
        {
            var host = raw
            if let scheme = host.range(of: "://") {
                host = String(host[scheme.upperBound...])
            }
            while host.hasSuffix("/") {
                host.removeLast()
            }
            // Strip any trailing path so the host stays just the
            // domain — the upstream `homepage` is occasionally a
            // full URL with a path (`/`, `/fr`, …).
            if let slash = host.firstIndex(of: "/") {
                host = String(host[..<slash])
            }
            if !host.isEmpty {
                return host
            }
        }
        guard !slug.isEmpty else { return "" }
        return "\(slug).vercel.app"
    }

    /// Best-effort primary color derivation. We scan the description
    /// + topics for a hex color of the form `#RRGGBB` (case-
    /// insensitive). Falls back to the default iris when none is
    /// found. A future iteration could pull the dominant color from
    /// the homepage favicon — out of scope for v1.0-alpha.11.
    public static func derivePrimaryColor(from repo: GitHubRepoSummary) -> String {
        let haystack = ([repo.description ?? ""] + repo.topics).joined(separator: " ")
        if let match = haystack.range(
            of: "#[0-9A-Fa-f]{6}",
            options: .regularExpression
        ) {
            return String(haystack[match]).uppercased()
        }
        return Self.defaultPrimaryColor
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

    /// v1.0-alpha.11 — `GET /user/repos?per_page=N&sort=pushed`. Returns
    /// the N most-recently-pushed repos the authenticated user owns
    /// or has explicit access to. Used by the Bulk Import wizard's
    /// scan step to enumerate what's available before fanning out
    /// `detectStack` + `extractMetadata` calls per repo.
    ///
    /// GitHub caps `per_page` at 100; the wizard's loop pulls a
    /// single page because Mehdi's portfolio sits well under that
    /// ceiling. Pagination is a future iteration.
    public func listMyRepos(limit: Int = 100) async throws -> [GitHubRepoSummary] {
        let token = try requireToken()
        guard let url = Self.userReposURL(limit: limit) else {
            throw GitHubClientError.decode
        }
        let request = signedRequest(url: url, token: token)
        let (data, response) = try await perform(request: request)
        guard (200..<300).contains(response) else {
            throw GitHubClientError.http(response)
        }
        do {
            let dtos = try JSONDecoder().decode([GitHubRepoSummaryDTO].self, from: data)
            return dtos.compactMap { $0.summary }
        } catch {
            throw GitHubClientError.decode
        }
    }

    /// v1.0-alpha.11 — Reads `package.json`, `vercel.json`,
    /// `composer.json`, plus a slim recursive tree, and returns a
    /// `RepoStackDetection` describing the framework family + a
    /// 0..1 confidence number. Soft-fails: a missing token returns
    /// a `.other` 0-confidence stub rather than throwing, matching
    /// every other v1.0-alpha.10 read.
    ///
    /// Decision tree (highest confidence wins):
    ///   1. `next` in `package.json` deps → nextjs (0.95)
    ///   2. `composer.json` + a `wp-content/` directory in the tree
    ///      → wordpress (0.9)
    ///   3. `wp-content/` in the tree alone → wordpress (0.7)
    ///   4. `theme.liquid` in the tree → shopify (0.9)
    ///   5. `_config.yml` (Jekyll) or `mkdocs.yml` in the root tree
    ///      → static (0.8)
    ///   6. Else → other (0.3)
    public func detectStack(repo: String) async throws -> RepoStackDetection {
        var signals: [String] = []
        let packageJSON = await readFile(repo: repo, path: "package.json")
        if let pkg = packageJSON, !pkg.isEmpty {
            signals.append("package.json present")
            if let dep = Self.nextDependencyVersion(in: pkg) {
                signals.append("package.json: next@\(dep)")
                if await !listDirectory(repo: repo, path: "").isEmpty {
                    // vercel.json is a strong corroborating signal
                    if await readFile(repo: repo, path: "vercel.json") != nil {
                        signals.append("vercel.json present")
                    }
                }
                return RepoStackDetection(
                    framework: "nextjs",
                    version: dep,
                    confidence: 0.95,
                    signals: signals
                )
            }
        }

        let composerJSON = await readFile(repo: repo, path: "composer.json")
        let tree = await recursiveTree(repo: repo, branch: "main")
        let hasWPContent = tree.contains { $0.path.contains("wp-content/") }
        if composerJSON != nil && hasWPContent {
            signals.append("composer.json present")
            signals.append("wp-content/ in tree")
            return RepoStackDetection(
                framework: "wordpress",
                version: nil,
                confidence: 0.9,
                signals: signals
            )
        }
        if hasWPContent {
            signals.append("wp-content/ in tree")
            return RepoStackDetection(
                framework: "wordpress",
                version: nil,
                confidence: 0.7,
                signals: signals
            )
        }

        if tree.contains(where: { $0.path.hasSuffix("theme.liquid") }) {
            signals.append("theme.liquid in tree")
            return RepoStackDetection(
                framework: "shopify",
                version: nil,
                confidence: 0.9,
                signals: signals
            )
        }

        if tree.contains(where: { $0.path == "_config.yml" }) {
            signals.append("_config.yml present (Jekyll)")
            return RepoStackDetection(
                framework: "static",
                version: nil,
                confidence: 0.8,
                signals: signals
            )
        }
        if tree.contains(where: { $0.path == "mkdocs.yml" }) {
            signals.append("mkdocs.yml present (MkDocs)")
            return RepoStackDetection(
                framework: "static",
                version: nil,
                confidence: 0.8,
                signals: signals
            )
        }

        if signals.isEmpty {
            signals.append("no recognised manifest")
        }
        return RepoStackDetection(
            framework: "other",
            version: nil,
            confidence: 0.3,
            signals: signals
        )
    }

    /// v1.0-alpha.11 — Orchestrator the wizard calls once per repo.
    /// Folds together:
    ///   1. `GET /repos/<repo>` for the slim `GitHubRepoSummary`
    ///   2. `detectStack(repo:)` for the framework verdict
    ///   3. `RepoMetadata.derive(repo:detection:)` for the slug /
    ///      name / host / color suggestions
    public func extractMetadata(repo: String) async throws -> RepoMetadata {
        let token = try requireToken()
        guard let url = Self.repoURL(repo: repo) else {
            throw GitHubClientError.decode
        }
        let request = signedRequest(url: url, token: token)
        let (data, status) = try await perform(request: request)
        guard (200..<300).contains(status) else {
            throw GitHubClientError.http(status)
        }
        let summary: GitHubRepoSummary
        do {
            let dto = try JSONDecoder().decode(GitHubRepoSummaryDTO.self, from: data)
            guard let value = dto.summary else { throw GitHubClientError.decode }
            summary = value
        } catch {
            throw GitHubClientError.decode
        }
        let detection = try await detectStack(repo: repo)
        return RepoMetadata.derive(repo: summary, detection: detection)
    }

    /// v1.0-alpha.11 — Tiny pure helper exposed for tests. Scans a
    /// `package.json` blob and returns the `next` dep version (or
    /// `nil` when absent). Strips the leading `^ / ~ / >=` operators
    /// so the call site can print a clean version string.
    public static func nextDependencyVersion(in packageJSON: String) -> String? {
        // Matches "next": "<version>" inside dependencies /
        // devDependencies blocks. Permissive on whitespace; tolerant
        // of trailing commas.
        let pattern = "\"next\"\\s*:\\s*\"([^\"]+)\""
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let nsrange = NSRange(packageJSON.startIndex..., in: packageJSON)
        guard let match = regex.firstMatch(in: packageJSON, range: nsrange),
              match.numberOfRanges >= 2,
              let range = Range(match.range(at: 1), in: packageJSON) else {
            return nil
        }
        var version = String(packageJSON[range])
        while let first = version.first, "^~>=<*".contains(first) {
            version.removeFirst()
        }
        version = version.trimmingCharacters(in: .whitespacesAndNewlines)
        return version.isEmpty ? nil : version
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

    /// v1.0-alpha.11 — `GET /user/repos?per_page=N&sort=pushed`.
    /// Capped at 100 by GitHub. Anything tighter just shortens the
    /// page; anything wider is silently capped server-side.
    public static func userReposURL(limit: Int) -> URL? {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("user/repos"),
            resolvingAgainstBaseURL: false
        )
        let clamped = max(1, min(limit, 100))
        components?.queryItems = [
            URLQueryItem(name: "per_page", value: "\(clamped)"),
            URLQueryItem(name: "sort", value: "pushed"),
            URLQueryItem(name: "direction", value: "desc"),
            URLQueryItem(name: "affiliation", value: "owner,collaborator,organization_member"),
        ]
        return components?.url
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

/// v1.0-alpha.11 — Wire shape for `GET /user/repos` and `GET /repos/<repo>`.
/// We project every column the wizard needs to render + every column
/// downstream `RepoMetadata.derive` reads. Soft-defaults absent
/// fields the same way `GitHubCommitDTO` does so a quirky upstream
/// payload doesn't kill the whole list.
private struct GitHubRepoSummaryDTO: Decodable {
    let full_name: String?
    let name: String?
    let description: String?
    let `private`: Bool?
    let default_branch: String?
    let pushed_at: String?
    let homepage: String?
    let stargazers_count: Int?
    let topics: [String]?

    var summary: GitHubRepoSummary? {
        guard let full_name, !full_name.isEmpty,
              let name, !name.isEmpty else {
            return nil
        }
        let date: Date
        if let raw = pushed_at {
            date = ISO8601DateFormatter().date(from: raw) ?? Date(timeIntervalSince1970: 0)
        } else {
            date = Date(timeIntervalSince1970: 0)
        }
        let homepageURL: String?
        if let h = homepage?.trimmingCharacters(in: .whitespacesAndNewlines), !h.isEmpty {
            homepageURL = h
        } else {
            homepageURL = nil
        }
        return GitHubRepoSummary(
            fullName: full_name,
            name: name,
            description: description,
            isPrivate: self.`private` ?? false,
            defaultBranch: default_branch ?? "main",
            pushedAt: date,
            homepageURL: homepageURL,
            stars: stargazers_count ?? 0,
            topics: topics ?? []
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
