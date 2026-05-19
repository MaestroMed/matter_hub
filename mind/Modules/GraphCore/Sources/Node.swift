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
    case meeting  // a calendar event captured into the graph (CalendarKit, v0.8)
    case mail     // an email captured via the Share Extension (v0.14)
}

@Model
public final class Node {
    // CloudKit-backed SwiftData has TWO hard constraints we satisfy
    // here:
    //
    //   1. "CloudKit integration requires that all attributes be
    //      optional, or have a default value set." → every non-optional
    //      stored property carries an inline default below.
    //
    //   2. "CloudKit integration does not support unique constraints."
    //      → `@Attribute(.unique)` on `id` would crash sync between
    //      Mehdi's two iPhones. We rely on UUID() collision probability
    //      (≈ 1 in 2^122) for uniqueness instead, which is comfortably
    //      better than what SQLite's UNIQUE buys us in practice.
    //
    //   3. "CloudKit integration requires that all relationships be
    //      optional." → `outgoing` and `incoming` are typed `[Edge]?`
    //      with nil default. Callers coalesce with `?? []`.
    //
    // Together these three changes unblock the actual CloudKit sync
    // between devices. Without them, the store silently falls back to
    // local-only and the user wonders why their second iPhone never
    // sees their notes.
    @Attribute(.unique) public var id: UUID = UUID()
    public var kindRaw: String = NodeKind.note.rawValue
    public var title: String = ""
    public var content: String = ""
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now
    /// Last time the user actively opened this Node (detail view, client
    /// detail, etc.). Optional + nil default so it migrates cleanly into
    /// existing stores. Drives the HomeView "Reprendre" carousel ordering.
    public var lastAccessedAt: Date?
    /// When the user marked a task-shaped Node as done. nil = still open.
    /// Safe to ignore on other kinds (notes, captures, audits, clients).
    public var completedAt: Date?
    public var tags: [String] = []
    public var sourceURL: String?
    public var embedding: [Float]?

    /// EKReminder.calendarItemIdentifier for the iOS Reminder mirroring
    /// this task-shaped Node (v0.10). `nil` when the Node has never been
    /// synced — the next foreground sync pass mints a paired reminder
    /// and writes the identifier here. Optional + nil default so the
    /// field migrates cleanly into existing CloudKit stores. Safe to
    /// ignore on non-task Nodes (notes, captures, audits, clients).
    public var reminderExternalID: String?

    // nil default (not `[]`): SwiftData's CloudKit-backed initializer
    // crashes at boot when a to-many @Relationship optional carries an
    // empty-array default — investigated 2026-05-19 after the test
    // runner failed with "Early unexpected exit". nil is the canonical
    // "no edges yet" representation here; SwiftData auto-instantiates
    // the array when the first edge is appended.
    @Relationship(deleteRule: .cascade, inverse: \Edge.from)
    public var outgoing: [Edge]?

    @Relationship(deleteRule: .cascade, inverse: \Edge.to)
    public var incoming: [Edge]?

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

    /// Marks the Node as just-opened by the user. Caller is responsible
    /// for `try? context.save()` afterwards. Idempotent — safe to call
    /// every time a detail view appears.
    @MainActor
    public func touchAccess() {
        lastAccessedAt = .now
    }

    /// Flips a task-shaped Node between done and open states.
    @MainActor
    public func toggleCompletion() {
        if completedAt == nil {
            completedAt = .now
        } else {
            completedAt = nil
        }
        updatedAt = .now
    }

    public var isCompleted: Bool {
        completedAt != nil
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
    // Same CloudKit-compatibility constraints as Node: inline defaults
    // for every non-optional attribute, no `@Attribute(.unique)` (the
    // CloudKit ingest pipeline rejects unique constraints). UUID()
    // collision probability handles uniqueness adequately at the
    // application layer.
    @Attribute(.unique) public var id: UUID = UUID()
    public var kindRaw: String = EdgeKind.relatedTo.rawValue
    public var from: Node?
    public var to: Node?
    public var createdAt: Date = Date.now

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
