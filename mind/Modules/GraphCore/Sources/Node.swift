import Foundation
import SwiftData

public enum NodeKind: String, Codable, CaseIterable, Sendable {
    case note
    case task
    case event
    case person
    case place
    case file
    case idea
    case habit
    case goal
    case journal
    case capture
    case client   // an organization / brand / prospect being tracked
    case audit    // a full digital audit report attached to a client
}

@Model
public final class Node {
    @Attribute(.unique) public var id: UUID
    public var kindRaw: String
    public var title: String
    public var content: String
    public var createdAt: Date
    public var updatedAt: Date
    public var tags: [String]
    public var sourceURL: String?
    public var embedding: [Float]?

    @Relationship(deleteRule: .cascade, inverse: \Edge.from)
    public var outgoing: [Edge] = []

    @Relationship(deleteRule: .cascade, inverse: \Edge.to)
    public var incoming: [Edge] = []

    public init(
        id: UUID = UUID(),
        kind: NodeKind,
        title: String,
        content: String = "",
        tags: [String] = [],
        sourceURL: String? = nil
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.title = title
        self.content = content
        self.createdAt = .now
        self.updatedAt = .now
        self.tags = tags
        self.sourceURL = sourceURL
    }

    public var kind: NodeKind {
        get { NodeKind(rawValue: kindRaw) ?? .note }
        set { kindRaw = newValue.rawValue }
    }
}

public enum EdgeKind: String, Codable, CaseIterable, Sendable {
    case references
    case child
    case mentions
    case relatedTo
    case derivedFrom
}

@Model
public final class Edge {
    @Attribute(.unique) public var id: UUID
    public var kindRaw: String
    public var from: Node?
    public var to: Node?
    public var createdAt: Date

    public init(id: UUID = UUID(), kind: EdgeKind, from: Node, to: Node) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.from = from
        self.to = to
        self.createdAt = .now
    }

    public var kind: EdgeKind {
        get { EdgeKind(rawValue: kindRaw) ?? .relatedTo }
        set { kindRaw = newValue.rawValue }
    }
}
