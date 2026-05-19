import Foundation
import GraphCore

/// Writes a freshly-built `ClientPortalArchive` to disk under a
/// destination root (typically
/// `~/Documents/client-portals/<archive.folderSlug>/`).
///
/// Kept as an `actor` so successive write-then-share gestures from the
/// AuditSheet can't race a half-written `index.html` onto the share
/// sheet. Every public method is `async`; the App layer awaits the
/// resulting folder URL before presenting `UIActivityViewController`.
public actor PortalWriter {

    public init() {}

    /// Writes every file in the archive under
    /// `destinationRoot.appendingPathComponent(archive.folderSlug)`.
    /// Returns the freshly-written folder URL on success; throws if a
    /// directory could not be created or a file could not be written.
    ///
    /// The folder is created with `withIntermediateDirectories: true`
    /// so a missing `client-portals/` parent doesn't blow the call.
    /// Existing files are overwritten — running the same audit twice
    /// produces two timestamped folders (the timestamp is baked into
    /// the slug) so the user never loses an older portal.
    @discardableResult
    public func write(
        archive: ClientPortalArchive,
        under destinationRoot: URL
    ) async throws -> URL {
        let fm = FileManager.default
        let folderURL = destinationRoot.appendingPathComponent(archive.folderSlug, isDirectory: true)

        try fm.createDirectory(
            at: folderURL,
            withIntermediateDirectories: true
        )

        for path in archive.sortedFilePaths {
            guard let data = archive.files[path] else { continue }
            let fileURL = folderURL.appendingPathComponent(path)
            // Create any nested directory components that the path
            // implies — `assets/og.png` needs an `assets/` subfolder.
            let parent = fileURL.deletingLastPathComponent()
            if parent.path != folderURL.path {
                try fm.createDirectory(
                    at: parent,
                    withIntermediateDirectories: true
                )
            }
            try data.write(to: fileURL, options: .atomic)
        }

        // Telemetry sink is @MainActor-isolated — hop off the actor
        // before posting the breadcrumb so the static var read stays
        // race-free. Fire-and-forget; the write succeeded already.
        let slug = archive.folderSlug
        let fileCount = archive.files.count
        let byteCount = archive.totalBytes
        await MainActor.run {
            MINDTelemetry.info(
                "clientPortal.written",
                data: [
                    "slug": slug,
                    "files": "\(fileCount)",
                    "bytes": "\(byteCount)",
                ]
            )
        }

        return folderURL
    }

    /// Convenience: the canonical "Documents/client-portals/" root that
    /// the App layer feeds into `write(archive:under:)`. Pure (no FS
    /// mutation) — `write` does the actual `createDirectory` call.
    public static func defaultDestinationRoot() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return docs.appendingPathComponent("client-portals", isDirectory: true)
    }
}
