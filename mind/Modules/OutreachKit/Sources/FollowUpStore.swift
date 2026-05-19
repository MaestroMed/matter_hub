import Foundation
import GraphCore  // MINDTelemetry

/// v0.29 — On-disk store for `FollowUpSequence` values.
///
/// Each sequence is persisted as `Documents/follow-ups/<uuid>.json`.
/// One file per sequence keeps writes lock-free at the OS level (the
/// store actor serialises concurrent writes anyway, but staying on
/// per-file granularity means a corrupt write of one sequence never
/// takes the whole follow-up state with it). An in-memory mirror
/// (`cache`) backs every read so the HomeView "Relances du jour"
/// card never round-trips through the filesystem on render.
///
/// Soft-fail strategy: every disk write that throws is downgraded to
/// a MINDTelemetry warning + an in-memory-only mutation. The next
/// successful write upgrades the in-memory state back to disk. The
/// caller never sees the failure — better to lose a sequence on
/// reboot than to surface "follow-up could not be scheduled" in the
/// middle of an outreach flow.
public actor FollowUpStore {

    /// Shared singleton — the app, the OutreachSheet toggle, the
    /// HomeView card, and `FollowUpScheduler.rescheduleAll` all reach
    /// this instance. Tests inject their own with a temp directory.
    public static let shared = FollowUpStore()

    /// Root directory holding every sequence JSON file. Lazily
    /// created on the first write. `Documents/follow-ups/`.
    private let rootURL: URL

    /// In-memory mirror of every sequence read so far. Populated on
    /// first access via `loadAllFromDisk()`; mutations write through
    /// to disk via `writeToDisk(_:)`.
    private var cache: [UUID: FollowUpSequence] = [:]
    /// Tracks whether we've hydrated `cache` from disk yet. The first
    /// public read hydrates, every subsequent read goes straight to
    /// `cache` (cheap).
    private var hydrated: Bool = false

    public init(
        rootURL: URL = FollowUpStore.defaultRootURL()
    ) {
        self.rootURL = rootURL
    }

    /// Default `Documents/follow-ups/` directory under the app
    /// sandbox. Static so the singleton + injected instances can
    /// share the same convention without duplicating the lookup.
    public nonisolated static func defaultRootURL() -> URL {
        let documents = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return documents.appendingPathComponent("follow-ups", isDirectory: true)
    }

    // MARK: - Public API

    /// Save (insert or replace) a sequence. Idempotent — the file is
    /// fully rewritten so a partial earlier write never sticks
    /// around. On disk failure, the mutation stays in-memory and a
    /// warning breadcrumb is emitted.
    public func save(_ sequence: FollowUpSequence) async {
        await hydrateIfNeeded()
        cache[sequence.id] = sequence
        writeToDisk(sequence)
    }

    /// Load a single sequence by id. Returns nil when the sequence
    /// has never been saved (or has been deleted). Soft-fails to nil
    /// when the on-disk file exists but is corrupt — the
    /// MINDTelemetry warning tells us about the regression without
    /// crashing the UI.
    public func load(_ id: UUID) async -> FollowUpSequence? {
        await hydrateIfNeeded()
        return cache[id]
    }

    /// All sequences with `status == .active` — the queue that
    /// HomeView, NodeDetailView, and `FollowUpScheduler.rescheduleAll`
    /// iterate. Order is unspecified; the caller sorts as needed.
    public func allActive() async -> [FollowUpSequence] {
        await hydrateIfNeeded()
        return cache.values.filter { $0.status == .active }
    }

    /// Every sequence currently in the cache, regardless of status.
    /// Used by tests + the rescheduler to inspect the full universe.
    public func allSequences() async -> [FollowUpSequence] {
        await hydrateIfNeeded()
        return Array(cache.values)
    }

    /// Pauses every active sequence whose `prospectNodeID` matches
    /// `prospectID` with `pausedReason = .replied`. Called by
    /// `NodeDetailView`'s "Marquer comme répondu" button. Returns the
    /// list of sequence ids that were flipped so the caller (the
    /// scheduler) can cancel their pending notifications in one pass.
    @discardableResult
    public func markReplied(prospectID: UUID, at when: Date = .now) async -> [UUID] {
        await hydrateIfNeeded()
        var affected: [UUID] = []
        for (id, var seq) in cache where seq.prospectNodeID == prospectID && seq.status == .active {
            seq.markReplied(at: when)
            cache[id] = seq
            writeToDisk(seq)
            affected.append(id)
        }
        if !affected.isEmpty {
            await telemetryInfo(
                "followUp.sequence.replied",
                data: [
                    "prospectID": prospectID.uuidString,
                    "count": "\(affected.count)",
                ]
            )
        }
        return affected
    }

    /// Marks the touch matching `touchID` (inside any sequence) as
    /// `.sent`. Returns the sequence id so callers can cancel that
    /// touch's pending notification. Cheap O(n*touchesPerSeq) scan;
    /// fine at expected scales (< 100 active sequences * 4 touches).
    @discardableResult
    public func markSent(touchID: UUID, at when: Date = .now) async -> UUID? {
        await hydrateIfNeeded()
        for (id, var seq) in cache {
            if seq.touches.contains(where: { $0.id == touchID }) {
                seq.markTouchSent(touchID: touchID, at: when)
                cache[id] = seq
                writeToDisk(seq)
                await telemetryInfo(
                    "followUp.touch.markedDone",
                    data: [
                        "sequenceID": id.uuidString,
                        "touchID": touchID.uuidString,
                    ]
                )
                return id
            }
        }
        return nil
    }

    /// Marks the touch matching `touchID` as `.skipped`. Same shape
    /// as `markSent`, used by the "Reporter" / "Stop" actions on the
    /// HomeView card rows.
    @discardableResult
    public func markSkipped(touchID: UUID) async -> UUID? {
        await hydrateIfNeeded()
        for (id, var seq) in cache {
            if seq.touches.contains(where: { $0.id == touchID }) {
                seq.markTouchSkipped(touchID: touchID)
                cache[id] = seq
                writeToDisk(seq)
                return id
            }
        }
        return nil
    }

    /// Deletes the sequence file + cache entry. Used by Settings →
    /// Danger zone (future) and by tests. Soft-fail.
    public func delete(_ id: UUID) async {
        cache.removeValue(forKey: id)
        let url = fileURL(for: id)
        try? FileManager.default.removeItem(at: url)
    }

    /// Removes every persisted sequence. Used by tests + the Settings
    /// "Clear all data" path.
    public func clearAll() async {
        cache.removeAll()
        try? FileManager.default.removeItem(at: rootURL)
        hydrated = true  // empty cache is a valid hydrated state
    }

    // MARK: - Disk I/O

    private func hydrateIfNeeded() async {
        guard !hydrated else { return }
        hydrated = true
        let fm = FileManager.default
        guard fm.fileExists(atPath: rootURL.path) else { return }
        let urls: [URL]
        do {
            urls = try fm.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        } catch {
            await telemetryWarning(
                "followUp.store.hydrate.failed",
                data: ["error": String(describing: error)]
            )
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for url in urls where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url) else { continue }
            do {
                let sequence = try decoder.decode(FollowUpSequence.self, from: data)
                cache[sequence.id] = sequence
            } catch {
                await telemetryWarning(
                    "followUp.store.decode.failed",
                    data: [
                        "file": url.lastPathComponent,
                        "error": String(describing: error),
                    ]
                )
            }
        }
    }

    private func writeToDisk(_ sequence: FollowUpSequence) {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        } catch {
            Task { await telemetryWarning(
                "followUp.store.mkdir.failed",
                data: ["error": String(describing: error)]
            ) }
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(sequence)
            try data.write(to: fileURL(for: sequence.id), options: [.atomic])
        } catch {
            Task { await telemetryWarning(
                "followUp.store.write.failed",
                data: [
                    "sequenceID": sequence.id.uuidString,
                    "error": String(describing: error),
                ]
            ) }
        }
    }

    private func fileURL(for id: UUID) -> URL {
        rootURL.appendingPathComponent("\(id.uuidString).json", isDirectory: false)
    }

    // MARK: - Telemetry MainActor bridges

    /// `MINDTelemetry.info/warning` are MainActor-isolated; the actor
    /// hops through these wrappers so the breadcrumb fires on the
    /// MainActor without us pollutting the call sites with explicit
    /// `await MainActor.run { }` blocks.
    private func telemetryInfo(_ name: String, data: [String: String]) async {
        await MainActor.run { MINDTelemetry.info(name, data: data) }
    }

    private func telemetryWarning(_ name: String, data: [String: String]) async {
        await MainActor.run { MINDTelemetry.warning(name, data: data) }
    }
}
