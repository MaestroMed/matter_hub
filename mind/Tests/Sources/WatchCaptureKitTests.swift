import XCTest
@testable import WatchCaptureKit
import GraphCore

/// v0.22.1 — Locks the pure substrate behind the deferred Watch
/// voice-capture surface. The watchOS App + CloudKit mirror plug into
/// the same shape later; every test here reflects a contract the
/// drain path on iPhone reads.
final class WatchCaptureKitTests: XCTestCase {

    // MARK: - WatchCaptureRecord

    /// A record persists every field round-trip through JSON
    /// (Codable). Critical because the queue writes one JSON file per
    /// record and the CloudKit mirror serialises the same shape.
    func test_record_codableRoundTrip_preservesEveryField() throws {
        let id = UUID()
        let folded = UUID()
        let started = Date(timeIntervalSince1970: 1_716_000_000)
        let original = WatchCaptureRecord(
            id: id,
            startedAt: started,
            durationSeconds: 12.5,
            transcript: "appeler le client demain",
            origin: .watch,
            status: .synced,
            foldedNodeID: folded
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(WatchCaptureRecord.self, from: data)

        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.startedAt, started)
        XCTAssertEqual(decoded.durationSeconds, 12.5, accuracy: 0.001)
        XCTAssertEqual(decoded.transcript, "appeler le client demain")
        XCTAssertEqual(decoded.origin, .watch)
        XCTAssertEqual(decoded.status, .synced)
        XCTAssertEqual(decoded.foldedNodeID, folded)
    }

    /// Negative durations are clamped to zero — a programmer error
    /// (e.g. wall-clock subtraction with reordered timestamps) never
    /// shows the user a `-3s` capture label.
    func test_record_negativeDuration_clampsToZero() {
        let record = WatchCaptureRecord(
            startedAt: .now,
            durationSeconds: -5,
            transcript: "test",
            origin: .phoneSimulated
        )
        XCTAssertEqual(record.durationSeconds, 0)
    }

    /// `markSynced` returns a copy with status flipped + folded ID
    /// stamped. Original is unchanged (value-type semantics).
    func test_record_markSynced_returnsFlippedCopy() {
        let folded = UUID()
        let pending = WatchCaptureRecord(
            startedAt: .now,
            durationSeconds: 4,
            transcript: "hello",
            origin: .watch,
            status: .pending
        )

        let synced = pending.markSynced(foldedNodeID: folded)

        XCTAssertEqual(synced.status, .synced)
        XCTAssertEqual(synced.foldedNodeID, folded)
        XCTAssertEqual(synced.id, pending.id) // identity preserved
        XCTAssertEqual(pending.status, .pending) // original untouched
    }

    /// `markFailed` flips status to `.failed` and drops any folded ID.
    func test_record_markFailed_returnsFailedCopyAndClearsFolded() {
        let synced = WatchCaptureRecord(
            startedAt: .now,
            durationSeconds: 1,
            transcript: "x",
            origin: .watch,
            status: .synced,
            foldedNodeID: UUID()
        )
        let failed = synced.markFailed()
        XCTAssertEqual(failed.status, .failed)
        XCTAssertNil(failed.foldedNodeID)
    }

    /// Trimmed-empty transcripts report `hasUsableTranscript == false`
    /// so the drain skips them.
    func test_record_hasUsableTranscript_skipsWhitespaceOnly() {
        let blank = WatchCaptureRecord(
            startedAt: .now,
            durationSeconds: 1,
            transcript: "   \n  \t  ",
            origin: .watch
        )
        XCTAssertFalse(blank.hasUsableTranscript)

        let real = WatchCaptureRecord(
            startedAt: .now,
            durationSeconds: 1,
            transcript: "  voice note  ",
            origin: .watch
        )
        XCTAssertTrue(real.hasUsableTranscript)
    }

    /// The on-the-wire raw values of every enum are stable strings —
    /// changing them would break already-persisted JSON files on
    /// disk for existing users.
    func test_record_enumRawValues_areStable() {
        XCTAssertEqual(WatchCaptureRecord.Origin.watch.rawValue, "watch")
        XCTAssertEqual(WatchCaptureRecord.Origin.phoneSimulated.rawValue, "phoneSimulated")
        XCTAssertEqual(WatchCaptureRecord.Status.pending.rawValue, "pending")
        XCTAssertEqual(WatchCaptureRecord.Status.synced.rawValue, "synced")
        XCTAssertEqual(WatchCaptureRecord.Status.failed.rawValue, "failed")
    }

    // MARK: - WatchCaptureTranscriptAssembler

    /// Internal newlines + tabs collapse into single spaces; leading +
    /// trailing whitespace is stripped.
    func test_assemble_collapsesWhitespaceAndStripsControl() {
        let input = "  hello\n\nworld\t\ttwo\u{0007}bell  "
        let output = WatchCaptureTranscriptAssembler.assemble(input)
        XCTAssertEqual(output, "hello world two bell")
    }

    /// Already-clean input round-trips unchanged.
    func test_assemble_cleanInput_unchanged() {
        XCTAssertEqual(
            WatchCaptureTranscriptAssembler.assemble("call client tomorrow"),
            "call client tomorrow"
        )
    }

    /// Whitespace-only input returns an empty string.
    func test_assemble_whitespaceOnly_returnsEmpty() {
        XCTAssertEqual(WatchCaptureTranscriptAssembler.assemble("   \n\t "), "")
    }

    /// `assemble(from:)` picks the longest fragment (SFSpeech partials
    /// grow monotonically — the longest is always the most complete).
    func test_assembleFromFragments_picksLongest() {
        let fragments = ["hello", "hello world", "hi"]
        XCTAssertEqual(
            WatchCaptureTranscriptAssembler.assemble(from: fragments),
            "hello world"
        )
    }

    /// `assemble(from:)` returns `""` for an empty fragment array.
    func test_assembleFromFragments_empty_returnsEmpty() {
        XCTAssertEqual(WatchCaptureTranscriptAssembler.assemble(from: []), "")
    }

    /// Title derivation cuts at the first sentence ender (`.` / `?` /
    /// `!`) and trims.
    func test_deriveTitle_cutsAtFirstSentenceEnder() {
        let title = WatchCaptureTranscriptAssembler.deriveTitle(
            from: "Appeler Mehdi demain. Voir aussi le contrat."
        )
        XCTAssertEqual(title, "Appeler Mehdi demain")
    }

    /// Empty transcripts derive the fallback `"Capture vocale"` so the
    /// row always has a non-empty title.
    func test_deriveTitle_emptyTranscript_returnsFallback() {
        XCTAssertEqual(
            WatchCaptureTranscriptAssembler.deriveTitle(from: ""),
            "Capture vocale"
        )
        XCTAssertEqual(
            WatchCaptureTranscriptAssembler.deriveTitle(from: "   \n  "),
            "Capture vocale"
        )
    }

    /// Long single-sentence transcripts truncate to `maxLength` with a
    /// trailing ellipsis.
    func test_deriveTitle_truncatesLongTranscriptWithEllipsis() {
        let long = String(repeating: "a", count: 200)
        let title = WatchCaptureTranscriptAssembler.deriveTitle(
            from: long,
            maxLength: 60
        )
        XCTAssertEqual(title.count, 61) // 60 chars + ellipsis
        XCTAssertTrue(title.hasSuffix("…"))
    }

    // MARK: - WatchCaptureNodeBuilder

    /// A non-empty record produces a draft with `.capture` kind, the
    /// `"watch"` tag, and the derived title.
    func test_nodeBuilder_buildsCaptureDraftFromWatchRecord() {
        let record = WatchCaptureRecord(
            startedAt: .now,
            durationSeconds: 7,
            transcript: "Penser à relancer le client Stripe demain.",
            origin: .watch
        )

        let draft = WatchCaptureNodeBuilder.draft(for: record)
        XCTAssertNotNil(draft)
        XCTAssertEqual(draft?.kind, .capture)
        XCTAssertEqual(draft?.title, "Penser à relancer le client Stripe demain")
        XCTAssertEqual(draft?.tags, ["watch"])
        XCTAssertEqual(draft?.sourceRecordID, record.id)
        XCTAssertEqual(draft?.origin, .watch)
    }

    /// A `.phoneSimulated` record gains a `"simulated"` tag so the user
    /// can distinguish "actually from the watch" from "simulated from
    /// iPhone" in their captures list.
    func test_nodeBuilder_phoneSimulated_tagsAsSimulated() {
        let record = WatchCaptureRecord(
            startedAt: .now,
            durationSeconds: 3,
            transcript: "hello from iphone",
            origin: .phoneSimulated
        )
        let draft = WatchCaptureNodeBuilder.draft(for: record)
        XCTAssertEqual(draft?.tags, ["watch", "simulated"])
    }

    /// An empty transcript returns `nil` — the drain skips minting a
    /// blank `.capture` Node.
    func test_nodeBuilder_emptyTranscript_returnsNil() {
        let record = WatchCaptureRecord(
            startedAt: .now,
            durationSeconds: 1,
            transcript: "   ",
            origin: .watch
        )
        XCTAssertNil(WatchCaptureNodeBuilder.draft(for: record))
    }

    /// Very long transcripts clamp the content to `maxContentLength`
    /// with a trailing ellipsis. Title still cuts at the sentence
    /// boundary.
    func test_nodeBuilder_clampsLongContent() {
        let long = String(repeating: "x", count: WatchCaptureNodeBuilder.maxContentLength + 50)
        let record = WatchCaptureRecord(
            startedAt: .now,
            durationSeconds: 60,
            transcript: long,
            origin: .watch
        )
        let draft = WatchCaptureNodeBuilder.draft(for: record)
        XCTAssertNotNil(draft)
        XCTAssertEqual(draft?.content.count, WatchCaptureNodeBuilder.maxContentLength + 1) // +1 for the ellipsis
        XCTAssertTrue(draft?.content.hasSuffix("…") ?? false)
    }

    // MARK: - WatchCaptureQueue

    /// Enqueueing a record writes a JSON file under
    /// `watch-capture-queue/<id>.json` and `loadAll` reads it back.
    func test_queue_enqueueAndLoad_roundTrips() async throws {
        let root = makeTempRoot()
        let queue = WatchCaptureQueue(rootDirectory: root)

        let record = WatchCaptureRecord(
            startedAt: Date(timeIntervalSince1970: 1_716_000_000),
            durationSeconds: 4,
            transcript: "first capture",
            origin: .watch
        )

        _ = try await queue.enqueue(record)
        let loaded = try await queue.loadAll()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, record.id)
        XCTAssertEqual(loaded.first?.transcript, "first capture")
    }

    /// `loadAll` sorts newest-first by `startedAt` so the SwiftUI list
    /// reads top-down.
    func test_queue_loadAll_sortsNewestFirst() async throws {
        let root = makeTempRoot()
        let queue = WatchCaptureQueue(rootDirectory: root)

        let older = WatchCaptureRecord(
            startedAt: Date(timeIntervalSince1970: 1_000_000),
            durationSeconds: 1,
            transcript: "older",
            origin: .watch
        )
        let newer = WatchCaptureRecord(
            startedAt: Date(timeIntervalSince1970: 2_000_000),
            durationSeconds: 1,
            transcript: "newer",
            origin: .watch
        )

        _ = try await queue.enqueue(older)
        _ = try await queue.enqueue(newer)

        let loaded = try await queue.loadAll()
        XCTAssertEqual(loaded.map(\.transcript), ["newer", "older"])
    }

    /// Enqueuing the same record ID twice overwrites — used by
    /// `markSynced` + `markFailed` to update an existing record in
    /// place.
    func test_queue_enqueueIdempotentOnId() async throws {
        let root = makeTempRoot()
        let queue = WatchCaptureQueue(rootDirectory: root)

        let id = UUID()
        let v1 = WatchCaptureRecord(
            id: id,
            startedAt: .now,
            durationSeconds: 1,
            transcript: "v1",
            origin: .watch,
            status: .pending
        )
        _ = try await queue.enqueue(v1)

        let v2 = v1.markSynced(foldedNodeID: UUID())
        _ = try await queue.enqueue(v2)

        let loaded = try await queue.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.status, .synced)
    }

    /// `pending()` returns only records still pending.
    func test_queue_pending_filtersByStatus() async throws {
        let root = makeTempRoot()
        let queue = WatchCaptureQueue(rootDirectory: root)

        let pending = WatchCaptureRecord(
            startedAt: Date(timeIntervalSince1970: 1_000),
            durationSeconds: 1,
            transcript: "pending",
            origin: .watch,
            status: .pending
        )
        let synced = WatchCaptureRecord(
            startedAt: Date(timeIntervalSince1970: 2_000),
            durationSeconds: 1,
            transcript: "synced",
            origin: .watch,
            status: .synced,
            foldedNodeID: UUID()
        )
        _ = try await queue.enqueue(pending)
        _ = try await queue.enqueue(synced)

        let pendingOnly = try await queue.pending()
        XCTAssertEqual(pendingOnly.count, 1)
        XCTAssertEqual(pendingOnly.first?.transcript, "pending")
    }

    /// `remove(id:)` drops the file from disk; subsequent loads omit it.
    func test_queue_remove_deletesFromDisk() async throws {
        let root = makeTempRoot()
        let queue = WatchCaptureQueue(rootDirectory: root)

        let record = WatchCaptureRecord(
            startedAt: .now,
            durationSeconds: 1,
            transcript: "remove me",
            origin: .watch
        )
        _ = try await queue.enqueue(record)
        let beforeCount = try await queue.loadAll().count
        XCTAssertEqual(beforeCount, 1)

        try await queue.remove(id: record.id)
        let afterCount = try await queue.loadAll().count
        XCTAssertEqual(afterCount, 0)
        let empty = try await queue.isEmpty()
        XCTAssertTrue(empty)
    }

    /// `remove(id:)` throws `recordNotFound` when the file is gone —
    /// caller can decide if that's a bug or a no-op.
    func test_queue_removeUnknownId_throwsRecordNotFound() async throws {
        let root = makeTempRoot()
        let queue = WatchCaptureQueue(rootDirectory: root)

        do {
            try await queue.remove(id: UUID())
            XCTFail("Expected throw")
        } catch let error as WatchCaptureQueue.QueueError {
            if case .recordNotFound = error {
                // expected
            } else {
                XCTFail("Wrong error: \(error)")
            }
        }
    }

    /// A non-JSON stray file in the queue folder is silently skipped —
    /// keeps `.DS_Store` and future siblings from breaking
    /// `loadAll`.
    func test_queue_loadAll_skipsNonJsonFiles() async throws {
        let root = makeTempRoot()
        let queue = WatchCaptureQueue(rootDirectory: root)

        let record = WatchCaptureRecord(
            startedAt: .now,
            durationSeconds: 1,
            transcript: "valid",
            origin: .watch
        )
        _ = try await queue.enqueue(record)

        // Drop a stray non-JSON file alongside.
        let queueRoot = await queue.rootDirectoryURL
        let stray = queueRoot.appendingPathComponent(".DS_Store")
        try Data("not json".utf8).write(to: stray)

        let loaded = try await queue.loadAll()
        XCTAssertEqual(loaded.count, 1)
    }

    /// `record(id:)` returns `nil` for unknown IDs rather than
    /// throwing — useful for the "tap to open folded node" path.
    func test_queue_recordById_returnsNilForUnknown() async throws {
        let root = makeTempRoot()
        let queue = WatchCaptureQueue(rootDirectory: root)
        let result = try await queue.record(id: UUID())
        XCTAssertNil(result)
    }

    // MARK: - Helpers

    private func makeTempRoot(function: String = #function) -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("WatchCaptureKitTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
}
