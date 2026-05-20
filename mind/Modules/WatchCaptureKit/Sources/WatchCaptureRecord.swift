import Foundation

/// v0.22.1 — Pure wire format for a single voice capture mint that
/// originated (or is *simulated* as originating) from the Apple Watch
/// "Capture" view. Ships as the substrate behind the deferred Watch
/// surface ahead of the watchOS target itself — same model
/// v0.31.1 / v1.0-alpha.8 used (forecast / health pulse): lock the
/// value type + the queue + the Node derivation, gate them with tests,
/// then a future iteration just adds the watchOS App extension and
/// the CloudKit mirror without re-rolling the data shape.
///
/// Design intent
/// -------------
/// - **Pure value type all the way down**: no `SFSpeech`, no
///   `AVAudioEngine`, no SwiftData. The record is just JSON-on-the-wire,
///   so it crosses watchOS ↔ iPhone (eventually CloudKit), and SwiftUI
///   ↔ tests with zero isolation friction.
/// - **Codable + Sendable + Hashable** so it can be enqueued onto an
///   actor-backed queue, persisted atomically, and diffed in tests
///   against a canonical fixture.
/// - **Origin-tagged**: until the watchOS target lands, the iPhone app
///   *simulates* a Watch capture (mic on iPhone, same UX) and stamps the
///   record with `.phoneSimulated`. When the real Watch ships, it stamps
///   `.watch`. The iPhone drain logic doesn't care which — both shape
///   into the same `.capture` Node — but the badge surfaces the origin
///   so the user can verify their watch is actually in the loop.
public struct WatchCaptureRecord: Codable, Sendable, Hashable, Identifiable {

    /// Where this capture was minted. The future watchOS target stamps
    /// `.watch`; the iPhone "simulate Watch capture" surface stamps
    /// `.phoneSimulated`. Tests rely on the raw value being stable
    /// (`"watch"` / `"phoneSimulated"`) so a fixture round-trip locks
    /// the wire shape.
    public enum Origin: String, Codable, Sendable, Hashable, CaseIterable {
        case watch
        case phoneSimulated
    }

    /// Pipeline state. A freshly-minted capture is `.pending` and waits
    /// for the iPhone drain to fold it into a `.capture` Node; once
    /// folded, it flips to `.synced`. If the mint itself failed (empty
    /// transcript, recogniser unavailable, etc.) the record still ships
    /// with `.failed` so the user can see *something* in the queue
    /// instead of a silent drop.
    public enum Status: String, Codable, Sendable, Hashable, CaseIterable {
        case pending
        case synced
        case failed
    }

    /// Stable identity for the record. Minted at capture time so the
    /// CloudKit mirror (future) and the on-disk queue can both
    /// deduplicate on the same string.
    public let id: UUID

    /// Wall-clock time the recording started. Drives the queue-side
    /// sort (newest first by default) and the optional "captured at
    /// HH:mm" caption when the record renders as a row.
    public let startedAt: Date

    /// Duration of the recording in seconds. Clamped to `>= 0`
    /// at construction — a negative duration is a programmer error.
    public let durationSeconds: Double

    /// Final transcript text, already assembled via
    /// `WatchCaptureTranscriptAssembler.assemble(_:)`. May be empty
    /// (the recogniser produced nothing) — the `Status` field captures
    /// the failure separately.
    public let transcript: String

    /// Where this capture came from (`.watch` / `.phoneSimulated`).
    public let origin: Origin

    /// Pipeline state (`.pending` / `.synced` / `.failed`).
    public let status: Status

    /// Optional UUID of the `.capture` Node the iPhone drain wrote
    /// when it folded this record into the graph. `nil` while
    /// `.pending` / `.failed`. Allows the future "tap a queued capture
    /// to open the Node" affordance without a secondary lookup.
    public let foldedNodeID: UUID?

    public init(
        id: UUID = UUID(),
        startedAt: Date,
        durationSeconds: Double,
        transcript: String,
        origin: Origin,
        status: Status = .pending,
        foldedNodeID: UUID? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.durationSeconds = max(0, durationSeconds)
        self.transcript = transcript
        self.origin = origin
        self.status = status
        self.foldedNodeID = foldedNodeID
    }

    /// Returns a copy of this record with the status flipped to
    /// `.synced` and `foldedNodeID` populated. Used by the iPhone
    /// drain after it folds the transcript into a `.capture` Node.
    public func markSynced(foldedNodeID: UUID) -> WatchCaptureRecord {
        WatchCaptureRecord(
            id: id,
            startedAt: startedAt,
            durationSeconds: durationSeconds,
            transcript: transcript,
            origin: origin,
            status: .synced,
            foldedNodeID: foldedNodeID
        )
    }

    /// Returns a copy of this record flipped to `.failed`. Used when
    /// the mint itself collapsed (recogniser unavailable, permission
    /// denied) so the queue still records the attempt instead of
    /// silently dropping it.
    public func markFailed() -> WatchCaptureRecord {
        WatchCaptureRecord(
            id: id,
            startedAt: startedAt,
            durationSeconds: durationSeconds,
            transcript: transcript,
            origin: origin,
            status: .failed,
            foldedNodeID: nil
        )
    }

    /// Convenience: `true` when this record has a non-empty trimmed
    /// transcript. Used by the drain to skip empty captures rather
    /// than litter the graph with zero-content `.capture` Nodes.
    public var hasUsableTranscript: Bool {
        !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
