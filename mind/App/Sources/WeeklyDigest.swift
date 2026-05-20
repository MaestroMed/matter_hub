import Foundation
import GraphCore

/// v0.16 — Weekly digest value type rendered as a non-disruptive Home
/// card on Sunday evenings (and the lingering Monday-morning window).
/// Pure data: every field is computed by `WeeklyDigestBuilder.compute`
/// from the user's nodes and focus history, no I/O involved, so the
/// digest is trivially testable and instantly available the moment
/// HomeView appears.
///
/// `narrative` is the only "nice to have" field — an on-device
/// Foundation Models sentence generated asynchronously by
/// `OnDeviceIntelligence.weeklyNarrative(_:)`. The structured counts
/// render with or without it, so a slow / unavailable model never
/// blocks the user from seeing their week at a glance.
public struct WeeklyDigest: Sendable, Equatable {

    /// Start-of-week reference (typically `reference - 7 days`). The
    /// detail sheet uses it as the title anchor ("Semaine du 12 mai").
    public let weekOf: Date

    /// Number of capture/note Nodes created within the 7-day window.
    public let captureCount: Int

    /// Number of audit Nodes created within the 7-day window.
    public let auditCount: Int

    /// Total focus duration (in hours) summed across every
    /// `FocusSessionRecord.actualDurationSeconds` whose `completedAt`
    /// falls inside the 7-day window. Rounded once at the column
    /// render — kept as a Double here so the detail sheet can format
    /// `2h32` or `12 min` without re-querying.
    public let focusHours: Double

    /// First 5 capture/note titles within the window, sorted by
    /// `updatedAt` descending. Used by the card's narrative paragraph
    /// AND the detail sheet's "highlights" list. Capped at 5 by the
    /// builder so callers don't have to slice.
    public let highlightedCaptures: [String]

    /// Optional Foundation Models-generated 2-sentence French recap of
    /// the week. nil when the model isn't available, the request times
    /// out, or the counts are too small to be worth narrating. The
    /// card falls back to the localized "Une semaine bien remplie."
    /// when nil — never shows a model-shaped empty space.
    public let narrative: String?

    public init(
        weekOf: Date,
        captureCount: Int,
        auditCount: Int,
        focusHours: Double,
        highlightedCaptures: [String],
        narrative: String? = nil
    ) {
        self.weekOf = weekOf
        self.captureCount = captureCount
        self.auditCount = auditCount
        self.focusHours = focusHours
        self.highlightedCaptures = highlightedCaptures
        self.narrative = narrative
    }

    /// Whether the digest carries any data worth rendering. Three
    /// zeros + no highlights = card hides itself, same render gate
    /// as `WeeklySummary.isMeaningful` on the v0.9 health card.
    public var isMeaningful: Bool {
        captureCount > 0 || auditCount > 0 || focusHours > 0
    }

    /// Replaces `narrative` while keeping every other field. Used by
    /// the HomeView `.task` after the async Foundation Models call
    /// resolves — the structured digest is computed synchronously
    /// first, then the narrative arrives a beat later and the card
    /// re-renders.
    public func withNarrative(_ narrative: String?) -> WeeklyDigest {
        WeeklyDigest(
            weekOf: weekOf,
            captureCount: captureCount,
            auditCount: auditCount,
            focusHours: focusHours,
            highlightedCaptures: highlightedCaptures,
            narrative: narrative
        )
    }
}

/// Pure-function builder that aggregates Nodes + focus sessions into
/// a `WeeklyDigest`. No SwiftData fetch happens here — the caller
/// passes the arrays from a `@Query` snapshot, which keeps this
/// trivially unit-testable without spinning up a model container.
///
/// Strategy
/// --------
/// The 7-day window is `[reference - 7d, reference]`. Anything older
/// is silently ignored. `kind` discrimination uses `kindRaw` strings
/// (`"capture"`, `"note"`, `"audit"`) because that's what's stored in
/// SwiftData — comparing raw strings sidesteps the optional `kind`
/// accessor and is what every other call site in HomeView does for
/// the same reason.
public enum WeeklyDigestBuilder {

    /// Number of seconds in a 7-day rolling window.
    private static let weekSeconds: TimeInterval = 7 * 24 * 3600

    /// Cap on `highlightedCaptures` length. Keeps the card compact and
    /// the narrative prompt under the on-device model's context budget.
    private static let highlightLimit: Int = 5

    /// Build a digest. Pass `Date.now` as `reference` in production;
    /// tests can pin any date and observe the cutoff window behave
    /// deterministically.
    ///
    /// - Parameters:
    ///   - nodes: every Node in the user's graph (SwiftData @Query
    ///     snapshot). The function filters internally.
    ///   - focusSessions: every persisted FocusSessionRecord. Same
    ///     contract.
    ///   - reference: the "now" anchor for the 7-day window. Production
    ///     passes `.now`; tests pin it.
    public static func compute(
        nodes: [Node],
        focusSessions: [FocusSessionRecord],
        asOf reference: Date
    ) -> WeeklyDigest {
        let cutoff = reference.addingTimeInterval(-weekSeconds)

        // Captures / notes in window. We treat `.capture` and `.note`
        // as the same bucket because the v0.16 acceptance copy says
        // "5 things you captured this week" — the user doesn't care
        // whether it was a long-form note or a one-tap capture, only
        // that they hit "save".
        let nodesInWindow = nodes.filter { $0.createdAt >= cutoff }
        let captureCount = nodesInWindow.filter {
            $0.kindRaw == NodeKind.capture.rawValue
                || $0.kindRaw == NodeKind.note.rawValue
        }.count

        // Audits are surfaced as their own count — they're the "1 audit
        // completed" line in the ULTRAPLAN copy and represent significantly
        // more work per row than a capture, so the user wants to see them
        // tallied separately.
        let auditCount = nodesInWindow.filter {
            $0.kindRaw == NodeKind.audit.rawValue
        }.count

        // Sum focus duration (in hours) over completed sessions whose
        // `completedAt` falls inside the window. We don't subset by
        // `startDate` — a session that started Sunday evening and ended
        // Monday morning belongs to the week it finished.
        let focusInWindow = focusSessions.filter { $0.completedAt >= cutoff }
        let focusSeconds = focusInWindow.reduce(0.0) { acc, record in
            acc + record.actualDurationSeconds
        }
        let focusHours = focusSeconds / 3600.0

        // Top 5 highlighted captures/notes by `updatedAt` descending.
        // We sort the in-window subset (not the full `nodes`) so a
        // capture from 8 days ago that was recently edited doesn't
        // sneak into "this week". Empty titles are filtered so the
        // narrative prompt never has to deal with blank entries.
        let highlightedCaptures = nodesInWindow
            .filter {
                ($0.kindRaw == NodeKind.capture.rawValue
                    || $0.kindRaw == NodeKind.note.rawValue)
                    && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(highlightLimit)
            .map { $0.title }

        return WeeklyDigest(
            weekOf: cutoff,
            captureCount: captureCount,
            auditCount: auditCount,
            focusHours: focusHours,
            highlightedCaptures: Array(highlightedCaptures),
            narrative: nil
        )
    }
}
