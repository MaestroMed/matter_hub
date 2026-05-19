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

/// v0.30 — Pipeline Kanban stage for a `.client` Node.
///
/// MIND's CRM lives on top of the Universal Object Graph: any
/// client / prospect Node carries an optional `pipelineStage` that
/// places it on the Pipeline Kanban board. The seven cases below
/// model a standard B2B sales motion, with `won` and `lost` sitting
/// as parallel terminal columns at the right of the board.
///
/// `progressOrdinal` is the canonical "how far along the funnel" rank
/// used by `Pipeline*` tests + telemetry. `won` and `lost` share the
/// same ordinal (6) because both represent the same terminal stage of
/// the funnel — they just diverge on outcome.
public enum PipelineStage: String, Codable, CaseIterable, Sendable, Equatable, Hashable {
    case prospect
    case contacted
    case qualified
    case audit
    case pitch
    case won
    case lost

    /// Funnel position, 0..6. Higher = further along.
    /// `won` and `lost` share ordinal 6 — both are terminal.
    public var progressOrdinal: Int {
        switch self {
        case .prospect:  return 0
        case .contacted: return 1
        case .qualified: return 2
        case .audit:     return 3
        case .pitch:     return 4
        case .won:       return 5
        case .lost:      return 5
        }
    }

    /// True when this stage closes the deal (won or lost). Drives
    /// reporting + the lead score "active" filter on HomeView.
    public var isTerminal: Bool {
        self == .won || self == .lost
    }

    /// Stages excluding the terminal `.lost` column when surfacing
    /// the kanban left-to-right. `.lost` is rendered parallel to
    /// `.won` in PipelineView but participates in `allCases` for
    /// the data-layer round-trip tests.
    public static var pipelineOrdered: [PipelineStage] {
        [.prospect, .contacted, .qualified, .audit, .pitch, .won, .lost]
    }
}

/// v0.30 — Pure descriptor returned by `PipelineActions.action(for:)`
/// so the action a stage triggers on drop is unit-testable without
/// instantiating the SwiftUI view. The PipelineView switch maps each
/// case onto the matching sheet / alert / toast presentation. Living
/// in GraphCore keeps the test target's import surface tight.
public enum PipelineStageAction: String, Sendable, Equatable, Hashable {
    /// `.prospect` drop — neutral, no auto-sheet (the user is just
    /// triaging back to the funnel start).
    case none
    /// `.contacted` drop — present OutreachSheet which mints a v0.29
    /// `FollowUpSequence` for the prospect.
    case openOutreachSequence
    /// `.audit` drop — present AuditSheet pre-seeded with the client's
    /// URL so the probes start one tap later.
    case openAuditSheet
    /// `.pitch` drop — present OutreachSheet with the "pitch" angle
    /// pre-selected (uses the audit context if one is attached).
    case openPitchSheet
    /// `.won` drop — confetti haptic + Stripe invoice template sheet.
    case celebrateAndInvoice
    /// `.lost` drop — alert asking for the reason, persisted as a tag
    /// `lost:<reason>` on the Node.
    case askLostReason
}

/// v0.30 — Pure mapping of stages to their auto-action descriptor.
/// `PipelineView.triggerActions(for:newStage:)` calls this and then
/// dispatches the UI side-effect. Pure function + no UI imports →
/// fully unit-testable.
public enum PipelineActions {
    public static func action(for stage: PipelineStage) -> PipelineStageAction {
        switch stage {
        case .prospect:  return .none
        case .contacted: return .openOutreachSequence
        case .audit:     return .openAuditSheet
        case .pitch:     return .openPitchSheet
        case .qualified: return .none
        case .won:       return .celebrateAndInvoice
        case .lost:      return .askLostReason
        }
    }
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

    /// v0.30 — Pipeline Kanban stage for a `.client` / prospect Node.
    /// Stored as raw String so CloudKit-backed SwiftData can sync it
    /// without a custom Codable type at the SwiftData boundary. `nil`
    /// means "unplaced" (the Node hasn't been triaged onto the kanban
    /// yet — PipelineView surfaces it in the `Prospect` column for
    /// `.client` Nodes via the `pipelineStage ?? .prospect` fallback).
    /// Safe to ignore on non-client kinds.
    public var pipelineStageRaw: String?

    /// v0.30 — Most recent kanban transition timestamp. Drives the
    /// "last activity" timestamp on each PipelineCard and the
    /// `pipeline.won` telemetry's elapsed-days computation (won timestamp
    /// minus first-seen creation timestamp).
    public var pipelineStageUpdatedAt: Date?

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

    /// v0.30 — Strongly-typed pipeline stage. `nil` round-trips through
    /// the raw `nil` (not the `.prospect` default) so callers can
    /// distinguish "never placed on the board" from "explicitly
    /// triaged back to Prospect". The setter mirrors the value into
    /// `pipelineStageRaw` *and* refreshes `pipelineStageUpdatedAt` so
    /// the kanban card timestamps stay accurate without extra glue
    /// in the call sites.
    public var pipelineStage: PipelineStage? {
        get {
            guard let raw = pipelineStageRaw else { return nil }
            return PipelineStage(rawValue: raw)
        }
        set {
            pipelineStageRaw = newValue?.rawValue
            pipelineStageUpdatedAt = .now
            updatedAt = .now
        }
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
