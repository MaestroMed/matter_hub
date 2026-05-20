import Foundation
import GraphCore

/// v0.22.1 — Pure derivation that turns a `WatchCaptureRecord` into
/// a `WatchCapturedNodeDraft` — the shape the iPhone drain needs to
/// mint a `.capture` Node. Splitting "compute the draft" from "insert
/// the SwiftData Node" keeps the math testable without spinning up
/// a `ModelContainer` — the draft can round-trip through Codable
/// in tests and the live drain path just constructs `Node(kind:.capture, title:..., content:..., tags:...)`.
public enum WatchCaptureNodeBuilder {

    /// Maximum length of the body content section. SFSpeech transcripts
    /// can run unbounded — clamping here keeps the SwiftUI cells
    /// readable in the Captures list and matches the limit the existing
    /// iPhone `QuickCaptureSheet` uses.
    public static let maxContentLength = 5_000

    /// Tag attached to every Watch-originated capture so the user can
    /// filter the Captures list by `tag:watch`. Stable string —
    /// changing it would break user filters.
    public static let watchTag = "watch"

    /// Builds the draft for the supplied record. Returns `nil` when
    /// the record's transcript is empty (the drain skips it instead
    /// of minting a blank `.capture` Node).
    public static func draft(for record: WatchCaptureRecord) -> WatchCapturedNodeDraft? {
        guard record.hasUsableTranscript else { return nil }

        let title = WatchCaptureTranscriptAssembler.deriveTitle(from: record.transcript)
        let assembled = WatchCaptureTranscriptAssembler.assemble(record.transcript)
        let content = clamp(assembled, to: maxContentLength)

        var tags = [watchTag]
        if record.origin == .phoneSimulated { tags.append("simulated") }

        return WatchCapturedNodeDraft(
            sourceRecordID: record.id,
            kind: .capture,
            title: title,
            content: content,
            tags: tags,
            startedAt: record.startedAt,
            durationSeconds: record.durationSeconds,
            origin: record.origin
        )
    }

    // MARK: - Private

    private static func clamp(_ string: String, to maxLength: Int) -> String {
        guard string.count > maxLength else { return string }
        let cutoff = string.index(string.startIndex, offsetBy: maxLength)
        return string[..<cutoff] + "…"
    }
}

/// v0.22.1 — Pure descriptor of a `.capture` Node about to be inserted
/// into the SwiftData graph from a `WatchCaptureRecord`. Lives outside
/// `GraphCore` so a test target doesn't have to spin up a
/// `ModelContainer` to lock the derivation contract — the host app
/// constructs `Node(kind: draft.kind, title: draft.title, content:
/// draft.content, tags: draft.tags)` and pairs the resulting
/// `Node.id` into `WatchCaptureRecord.markSynced(foldedNodeID:)`.
public struct WatchCapturedNodeDraft: Codable, Sendable, Hashable {
    public let sourceRecordID: UUID
    public let kind: NodeKind
    public let title: String
    public let content: String
    public let tags: [String]
    public let startedAt: Date
    public let durationSeconds: Double
    public let origin: WatchCaptureRecord.Origin

    public init(
        sourceRecordID: UUID,
        kind: NodeKind,
        title: String,
        content: String,
        tags: [String],
        startedAt: Date,
        durationSeconds: Double,
        origin: WatchCaptureRecord.Origin
    ) {
        self.sourceRecordID = sourceRecordID
        self.kind = kind
        self.title = title
        self.content = content
        self.tags = tags
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.origin = origin
    }
}
