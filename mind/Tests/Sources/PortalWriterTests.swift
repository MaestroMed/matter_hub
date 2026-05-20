import XCTest
@testable import ClientPortalKit

/// Tests for the IO side of the Client Portal pipeline. Every test
/// writes to a fresh temp directory under `NSTemporaryDirectory()` so
/// runs stay hermetic — no leftover state between invocations.
final class PortalWriterTests: XCTestCase {

    private var tempRoot: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PortalWriterTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        if let root = tempRoot, FileManager.default.fileExists(atPath: root.path) {
            try? FileManager.default.removeItem(at: root)
        }
        try await super.tearDown()
    }

    // MARK: - Happy path

    func test_write_createsFolderAndIndexHTML() async throws {
        let writer = PortalWriter()
        let archive = ClientPortalArchive(
            files: ["index.html": Data("<html>hello</html>".utf8)],
            folderSlug: "test-slug-2026-05-19"
        )

        let folder = try await writer.write(archive: archive, under: tempRoot)

        XCTAssertEqual(folder.lastPathComponent, "test-slug-2026-05-19")

        let indexURL = folder.appendingPathComponent("index.html")
        XCTAssertTrue(FileManager.default.fileExists(atPath: indexURL.path),
                      "index.html must be on disk after write()")
        let body = try String(contentsOf: indexURL, encoding: .utf8)
        XCTAssertEqual(body, "<html>hello</html>")
    }

    func test_write_createsIntermediateDirectories() async throws {
        let writer = PortalWriter()
        // Use a nested temp root that doesn't exist yet — write() must
        // create every parent in one go.
        let deepRoot = tempRoot.appendingPathComponent("a/b/c", isDirectory: true)
        let archive = ClientPortalArchive(
            files: ["index.html": Data("<html>x</html>".utf8)],
            folderSlug: "site"
        )

        let folder = try await writer.write(archive: archive, under: deepRoot)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
    }

    func test_write_handlesNestedAssetPaths() async throws {
        let writer = PortalWriter()
        let archive = ClientPortalArchive(
            files: [
                "index.html": Data("<html></html>".utf8),
                "assets/css/main.css": Data("body{}".utf8),
            ],
            folderSlug: "nested-2026"
        )

        let folder = try await writer.write(archive: archive, under: tempRoot)
        let cssURL = folder.appendingPathComponent("assets/css/main.css")
        XCTAssertTrue(FileManager.default.fileExists(atPath: cssURL.path),
                      "Nested asset path must have its parent dirs created")
        let body = try String(contentsOf: cssURL, encoding: .utf8)
        XCTAssertEqual(body, "body{}")
    }

    // MARK: - Defaults

    func test_defaultDestinationRoot_pointsAtDocumentsClientPortals() {
        let root = PortalWriter.defaultDestinationRoot()
        XCTAssertEqual(root.lastPathComponent, "client-portals",
                       "Default destination is 'Documents/client-portals/' — App layer relies on this")
    }
}
