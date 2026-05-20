import Foundation

/// v0.25.1 — Per-preset persistent layout store. The visionOS surface
/// (future) will let the user drag panels in 3D — those custom anchors
/// persist here so reopening the same preset hands the user back the
/// exact arrangement they left behind.
///
/// Storage layout
/// --------------
/// `<root>/spatial-layouts/<preset-rawValue>.json` — one JSON file per
/// preset. Lets a new preset's layout land via atomic write
/// (`.write(options: .atomic)`) without disturbing siblings.
///
/// Concurrency
/// -----------
/// Actor isolation so concurrent reads / writes from the future
/// visionOS surface stay consistent. Mirrors the `HealthPulseStore`
/// + `WatchCaptureQueue` shape so a regression in any of the three
/// surfaces is fixed by the same code review.
public actor SpatialLayoutStore {

    public enum StoreError: Error, Equatable {
        case rootCreationFailed
        case writeFailed(String)
        case loadFailed(String)
    }

    private let rootURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Spawns / wraps the store rooted at the supplied directory. The
    /// host app passes `URL.documentsDirectory` so layouts persist
    /// across launches; tests pass a hermetic temporary directory so
    /// each test gets an empty store.
    public init(rootDirectory: URL, fileManager: FileManager = .default) {
        self.rootURL = rootDirectory.appendingPathComponent("spatial-layouts", isDirectory: true)
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    /// Saves the supplied panels for the given preset. Idempotent —
    /// re-saving for the same preset overwrites the previous JSON.
    @discardableResult
    public func save(_ panels: [SpatialPanel], for preset: SpatialLayoutPreset) throws -> URL {
        try ensureRoot()
        let url = fileURL(for: preset)
        do {
            let data = try encoder.encode(panels)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            throw StoreError.writeFailed(error.localizedDescription)
        }
    }

    /// Loads the persisted layout for the supplied preset, or `nil`
    /// if no layout has been saved yet. Tested via `load(_:)` →
    /// `save(_:for:)` → `load(_:)` round-trip.
    public func load(_ preset: SpatialLayoutPreset) throws -> [SpatialPanel]? {
        try ensureRoot()
        let url = fileURL(for: preset)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode([SpatialPanel].self, from: data)
        } catch {
            throw StoreError.loadFailed(error.localizedDescription)
        }
    }

    /// Removes the saved layout for the supplied preset. Idempotent
    /// — a missing file is a no-op (returns `false`).
    @discardableResult
    public func delete(_ preset: SpatialLayoutPreset) throws -> Bool {
        let url = fileURL(for: preset)
        guard fileManager.fileExists(atPath: url.path) else { return false }
        try fileManager.removeItem(at: url)
        return true
    }

    /// Returns true when no layout has been persisted yet for any
    /// preset. Used by the future first-launch onboarding to know
    /// when to seed the default Bento layout.
    public func isEmpty() throws -> Bool {
        try ensureRoot()
        let entries = (try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return entries.filter { $0.pathExtension == "json" }.isEmpty
    }

    /// Exposes the on-disk root for diagnostics + tests.
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
            throw StoreError.rootCreationFailed
        }
    }

    private func fileURL(for preset: SpatialLayoutPreset) -> URL {
        rootURL.appendingPathComponent("\(preset.rawValue).json")
    }
}
