import Foundation

/// v0.22.1 — On-disk persistent queue for `WatchCaptureRecord` mints
/// waiting to be folded into the iPhone's SwiftData graph. The
/// future watchOS App writes records into the equivalent CloudKit
/// container; until that lands, the iPhone "simulate Watch capture"
/// surface writes here directly so the drain path is the same on
/// both sides of the bridge.
///
/// Storage layout
/// --------------
/// `<root>/watch-capture-queue/<record-id>.json` — one JSON file per
/// record, with the record ID as the filename. Lets a new record
/// land via atomic write (`.write(options:.atomic)`) without
/// disturbing siblings, and lets the drain walk the folder in any
/// order (the sort happens in memory after load).
///
/// Concurrency
/// -----------
/// The queue is an `actor` so every reader / writer hops onto the
/// same isolation domain — multiple captures landing simultaneously
/// stay consistent. Encoder / decoder are constructed once at init
/// and reused.
public actor WatchCaptureQueue {

    public enum QueueError: Error, Equatable {
        case rootCreationFailed
        case writeFailed(String)
        case loadFailed(String)
        case recordNotFound(UUID)
    }

    private let rootURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Spawns / wraps the queue rooted at the supplied directory. The
    /// host app passes `URL.documentsDirectory` so captures persist
    /// across launches; tests pass a hermetic
    /// `FileManager.default.temporaryDirectory.appending(...)` so
    /// each test gets an empty queue.
    public init(rootDirectory: URL, fileManager: FileManager = .default) {
        self.rootURL = rootDirectory.appendingPathComponent("watch-capture-queue", isDirectory: true)
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    /// Enqueue (or update) a record. Idempotent on `record.id` — a
    /// second call with the same ID overwrites the previous JSON,
    /// which is exactly what `markSynced` + `markFailed` need.
    @discardableResult
    public func enqueue(_ record: WatchCaptureRecord) throws -> URL {
        try ensureRoot()
        let url = fileURL(for: record.id)
        do {
            let data = try encoder.encode(record)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            throw QueueError.writeFailed(error.localizedDescription)
        }
    }

    /// Loads every record currently on disk. Sorted newest-first by
    /// `startedAt` so the SwiftUI list reads top-down. Skips any
    /// non-JSON entry silently — keeps the queue robust to
    /// `.DS_Store` or future stray sibling files.
    public func loadAll() throws -> [WatchCaptureRecord] {
        try ensureRoot()
        let entries: [URL]
        do {
            entries = try fileManager.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw QueueError.loadFailed(error.localizedDescription)
        }

        var records: [WatchCaptureRecord] = []
        for url in entries where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url) else { continue }
            guard let record = try? decoder.decode(WatchCaptureRecord.self, from: data) else { continue }
            records.append(record)
        }
        records.sort { lhs, rhs in
            lhs.startedAt > rhs.startedAt
        }
        return records
    }

    /// Returns records whose `status == .pending` — the drain path
    /// reads this list to know what to fold into the graph next.
    public func pending() throws -> [WatchCaptureRecord] {
        try loadAll().filter { $0.status == .pending }
    }

    /// Removes the record with the supplied ID. The drain calls this
    /// after a successful `markSynced` + Node-write to keep the
    /// queue tight — synced records aren't kept indefinitely.
    public func remove(id: UUID) throws {
        let url = fileURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else {
            throw QueueError.recordNotFound(id)
        }
        try fileManager.removeItem(at: url)
    }

    /// True when the queue has zero entries. Cheap helper for the
    /// SwiftUI empty-state branch.
    public func isEmpty() throws -> Bool {
        try loadAll().isEmpty
    }

    /// Resolves a single record by ID, or `nil` if the file is gone.
    public func record(id: UUID) throws -> WatchCaptureRecord? {
        let url = fileURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try decoder.decode(WatchCaptureRecord.self, from: data)
    }

    /// Exposes the on-disk root for diagnostics + tests. Not used by
    /// the SwiftUI surface.
    public var rootDirectoryURL: URL { rootURL }

    // MARK: - Private

    private func ensureRoot() throws {
        if fileManager.fileExists(atPath: rootURL.path) { return }
        do {
            try fileManager.createDirectory(
                at: rootURL,
                withIntermediateDirectories: true
            )
        } catch {
            throw QueueError.rootCreationFailed
        }
    }

    private func fileURL(for id: UUID) -> URL {
        rootURL.appendingPathComponent("\(id.uuidString).json")
    }
}
