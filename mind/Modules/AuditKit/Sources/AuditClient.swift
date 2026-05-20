import Foundation

/// Lightweight description of an organisation being audited. The reasoned
/// "Who are they exactly?" goes into the AuditReport.synthesis; this type
/// only carries the bare identity needed to launch and persist a run.
public struct AuditClient: Sendable, Identifiable, Codable, Hashable {
    public let id: UUID
    public let url: URL
    public let name: String?
    public let createdAt: Date

    /// v1.0-alpha.10 — Optional GitHub repo slug ("owner/name"). When
    /// non-nil, the AuditController fires the 14th probe (repository-
    /// aware audit) alongside the 13 URL probes; the report's
    /// `repoFindings` slot then carries the source-code signal that
    /// the AuditSheet "Code source" section + the portal HTML render.
    /// Backward-compatible Codable so audits saved before alpha.10
    /// keep round-tripping (missing key → nil).
    public let githubRepo: String?

    public init(
        id: UUID = UUID(),
        url: URL,
        name: String? = nil,
        createdAt: Date = .now,
        githubRepo: String? = nil
    ) {
        self.id = id
        self.url = url
        self.name = name
        self.createdAt = createdAt
        self.githubRepo = githubRepo
    }

    /// Best-effort human label, falling back to the host then the raw URL.
    public var displayName: String {
        if let name, !name.isEmpty { return name }
        if let host = url.host(percentEncoded: false) {
            return host.replacingOccurrences(of: "www.", with: "")
        }
        return url.absoluteString
    }

    // MARK: - Codable (backwards-compatible githubRepo)

    private enum CodingKeys: String, CodingKey {
        case id, url, name, createdAt, githubRepo
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.url = try c.decode(URL.self, forKey: .url)
        self.name = try c.decodeIfPresent(String.self, forKey: .name)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.githubRepo = try c.decodeIfPresent(String.self, forKey: .githubRepo)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(url, forKey: .url)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(githubRepo, forKey: .githubRepo)
    }
}
