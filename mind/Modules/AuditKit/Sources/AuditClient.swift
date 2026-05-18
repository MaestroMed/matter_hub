import Foundation

/// Lightweight description of an organisation being audited. The reasoned
/// "Who are they exactly?" goes into the AuditReport.synthesis; this type
/// only carries the bare identity needed to launch and persist a run.
public struct AuditClient: Sendable, Identifiable, Codable, Hashable {
    public let id: UUID
    public let url: URL
    public let name: String?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        url: URL,
        name: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.url = url
        self.name = name
        self.createdAt = createdAt
    }

    /// Best-effort human label, falling back to the host then the raw URL.
    public var displayName: String {
        if let name, !name.isEmpty { return name }
        if let host = url.host(percentEncoded: false) {
            return host.replacingOccurrences(of: "www.", with: "")
        }
        return url.absoluteString
    }
}
