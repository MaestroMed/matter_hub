import Foundation

/// In-memory bundle of files that compose a generated client portal.
///
/// The producer (`ClientPortalBuilder.generateSite(for:brand:)`) is
/// **pure** — no FileManager, no temp dirs — so it stays trivially
/// testable: every assertion in `ClientPortalBuilderTests` walks the
/// `files` dictionary directly without touching disk.
///
/// The consumer (`PortalWriter`) is the IO actor: it takes a freshly
/// built `ClientPortalArchive` plus a destination URL and lays the
/// bytes onto disk, returning the final folder URL the App layer
/// then hands to `UIActivityViewController` / `UIApplication.open(_:)`.
///
/// Each key is a forward-slashed relative path (e.g. `"index.html"`,
/// `"assets/og.png"`); the writer joins it onto the destination root
/// with `URL(fileURLWithPath:)` so the same archive can be unpacked
/// anywhere — Documents/, a Vercel deploy directory, a Mac sandbox
/// scratch folder — without the builder caring.
public struct ClientPortalArchive: Sendable, Hashable {

    /// Forward-slashed relative path → file bytes. Always non-empty
    /// (`index.html` is mandatory) and always sorted alphabetically
    /// when iterated for stable test snapshots.
    public let files: [String: Data]

    /// Human-friendly slug for the parent folder name —
    /// `"acme-corp-2026-05-19"`, used by the App layer to compose
    /// `Documents/client-portals/<slug>/`. The builder mints this from
    /// the audit's client display name + the generated-at date so
    /// successive runs for the same client get their own folders
    /// rather than overwriting each other.
    public let folderSlug: String

    /// Total size of `files` in bytes. Cached at construction time
    /// because the page-weight ceiling test asserts on it and we
    /// don't want every assertion to redundantly sum a dictionary.
    public let totalBytes: Int

    public init(files: [String: Data], folderSlug: String) {
        precondition(files["index.html"] != nil,
                     "ClientPortalArchive must contain index.html")
        self.files = files
        self.folderSlug = folderSlug
        self.totalBytes = files.values.reduce(0) { $0 + $1.count }
    }

    /// Convenience: the bytes of `index.html` (always present per the
    /// init precondition). Used by tests to assert on the rendered
    /// HTML string without re-decoding from the dict every time.
    public var indexHTML: String {
        guard let data = files["index.html"],
              let str = String(data: data, encoding: .utf8) else {
            return ""
        }
        return str
    }

    /// Sorted file paths for stable iteration in tests + a
    /// deterministic `PortalWriter` write order.
    public var sortedFilePaths: [String] {
        files.keys.sorted()
    }
}
