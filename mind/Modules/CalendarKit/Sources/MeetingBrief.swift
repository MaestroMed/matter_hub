import Foundation
import GraphCore

/// v0.28 — Discovery Call Prep Dossier.
///
/// Pure value bundle MIND assembles the day before any prospect /
/// client meeting so Mehdi walks in with three things ready: recent
/// company news, the relevant audit findings (if MIND has one), and
/// five calibrated discovery questions. The notification fires at
/// 7am local; the tap presents the `MeetingBriefSheet`.
///
/// We deliberately keep the model OUT of CalendarKit's `CalendarEvent`
/// even though every brief is anchored on one — the brief is a
/// snapshot frozen at generation time (news headlines, audit numbers,
/// attendee LinkedIn URLs). Recomputing it on every sheet open would
/// require re-running the LLM enrichment, which both costs money and
/// surfaces flicker. The same `MeetingBrief` instance is rendered
/// from the notification tap until the meeting starts.
///
/// Sendable + Equatable so the host App can hand it across the
/// MainActor boundary without ceremony, and tests can lock the
/// generated copy literally.
public struct MeetingBrief: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let event: CalendarEvent
    /// Sendable reference to the matched client Node. `nil` when no
    /// client matched (e.g. internal MIND meetings, new prospects
    /// whose domain isn't yet in the graph). We store the id + title
    /// instead of the `Node` reference because `@Model` types from
    /// SwiftData are class-bound, MainActor-isolated, and therefore
    /// non-Sendable — embedding one here would prevent the brief
    /// from crossing the actor boundary the enricher needs.
    public let detectedClient: DetectedClient?
    public let recentNews: [BriefBullet]
    public let auditHighlights: [BriefBullet]
    public let attendeeIntel: [AttendeeIntel]
    /// Always exactly 5 — the dossier guarantees a full discovery
    /// surface even when the heuristic falls back to the generic
    /// qualifying questions.
    public let discoveryQuestions: [String]
    public let elevatorOpening: String
    public let generatedAt: Date

    public init(
        id: UUID = UUID(),
        event: CalendarEvent,
        detectedClient: DetectedClient? = nil,
        recentNews: [BriefBullet] = [],
        auditHighlights: [BriefBullet] = [],
        attendeeIntel: [AttendeeIntel] = [],
        discoveryQuestions: [String],
        elevatorOpening: String,
        generatedAt: Date = .now
    ) {
        self.id = id
        self.event = event
        self.detectedClient = detectedClient
        self.recentNews = recentNews
        self.auditHighlights = auditHighlights
        self.attendeeIntel = attendeeIntel
        self.discoveryQuestions = discoveryQuestions
        self.elevatorOpening = elevatorOpening
        self.generatedAt = generatedAt
    }
}

/// Sendable snapshot of the client Node MIND matched against the
/// meeting attendees. Carries just the id + title + the small set
/// of metadata the sheet needs — the host App resolves the live
/// `Node` from `nodeID` when the user taps "Open client".
public struct DetectedClient: Sendable, Equatable, Hashable {
    public let nodeID: UUID
    public let title: String
    public let sourceURL: String?
    public let tags: [String]

    public init(
        nodeID: UUID,
        title: String,
        sourceURL: String? = nil,
        tags: [String] = []
    ) {
        self.nodeID = nodeID
        self.title = title
        self.sourceURL = sourceURL
        self.tags = tags
    }

    /// Convenience initializer that captures the small set of fields
    /// the sheet needs from a `Node` reference. The closure is
    /// expected to be called on the MainActor (where SwiftData lives)
    /// so the property reads are safe.
    @MainActor
    public init(node: Node) {
        self.nodeID = node.id
        self.title = node.title
        self.sourceURL = node.sourceURL ?? (node.content.isEmpty ? nil : node.content)
        self.tags = node.tags
    }
}

/// A single bullet in the brief — one fact, one optional source.
/// The source is rendered as a tap target in the sheet so Mehdi can
/// open the article that grounds the claim before the call starts.
public struct BriefBullet: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let text: String
    /// External URL ("https://techcrunch.com/…") or an internal
    /// sentinel ("internal:audit") so the sheet can route the tap.
    public let source: String?

    public init(
        id: UUID = UUID(),
        text: String,
        source: String? = nil
    ) {
        self.id = id
        self.text = text
        self.source = source
    }
}

/// Per-attendee research bundle. `role` and `linkedInURL` are
/// best-effort — pulled from email signatures cached in the graph
/// or, eventually, a LinkedIn API lookup. Nil-tolerant so we never
/// hide an attendee just because we couldn't enrich them.
public struct AttendeeIntel: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let email: String
    public let displayName: String
    public let role: String?
    public let linkedInURL: String?
    public let notes: String?

    public init(
        id: UUID = UUID(),
        email: String,
        displayName: String,
        role: String? = nil,
        linkedInURL: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.role = role
        self.linkedInURL = linkedInURL
        self.notes = notes
    }
}
