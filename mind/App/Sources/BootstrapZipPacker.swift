import Foundation
import BootstrapKit

/// v1.0-alpha.6 — Bootstrap Scaffolder.
///
/// IO helper that materialises an in-memory `BootstrapArchive` into
/// a real `.zip` on disk. Pure BootstrapKit is intentionally I/O-free;
/// this packer lives in the App target so the BootstrapKit module
/// stays trivially testable.
///
/// Implementation
/// --------------
/// 1. Lay out every `[String: Data]` file under a temporary directory
///    that mirrors the archive's `folderSlug` (so the .zip unpacks
///    into a single named folder, never into a mess of loose files).
/// 2. Ask `NSFileCoordinator` to coordinate a read with the
///    `.forUploading` option — that is the documented Apple-supported
///    way to obtain a zip-archive URL for an arbitrary directory
///    without bundling a third-party Zip library.
/// 3. Copy the resulting zip from the coordinator's transient URL to
///    the caller-supplied destination URL.
enum BootstrapZipPacker {

    enum PackError: Error {
        case stagingFailed
        case coordinationFailed(Error)
        case copyFailed(Error)
    }

    /// Writes `archive` as a `.zip` file at `destinationURL`. Overwrites
    /// any pre-existing file at that URL. Returns the resolved
    /// destination URL on success.
    @discardableResult
    static func write(archive: BootstrapArchive, to destinationURL: URL) throws -> URL {
        let fm = FileManager.default

        // 1. Stage under a temp directory that mirrors the folder slug.
        let stagingRoot = fm.temporaryDirectory
            .appendingPathComponent("mind-bootstrap-\(UUID().uuidString)", isDirectory: true)
        let folderRoot = stagingRoot.appendingPathComponent(archive.folderSlug, isDirectory: true)
        do {
            try fm.createDirectory(at: folderRoot, withIntermediateDirectories: true)
            for path in archive.sortedFilePaths {
                guard let data = archive.files[path] else { continue }
                let dest = folderRoot.appendingPathComponent(path)
                let parent = dest.deletingLastPathComponent()
                try fm.createDirectory(at: parent, withIntermediateDirectories: true)
                try data.write(to: dest, options: .atomic)
            }
        } catch {
            throw PackError.stagingFailed
        }
        defer { try? fm.removeItem(at: stagingRoot) }

        // 2. Coordinate a `.forUploading` read to obtain a zip URL.
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var copyError: Error?
        coordinator.coordinate(
            readingItemAt: folderRoot,
            options: [.forUploading],
            error: &coordinationError
        ) { zippedURL in
            do {
                if fm.fileExists(atPath: destinationURL.path) {
                    try fm.removeItem(at: destinationURL)
                }
                try fm.copyItem(at: zippedURL, to: destinationURL)
            } catch {
                copyError = error
            }
        }
        if let coordinationError {
            throw PackError.coordinationFailed(coordinationError)
        }
        if let copyError {
            throw PackError.copyFailed(copyError)
        }
        return destinationURL
    }
}
