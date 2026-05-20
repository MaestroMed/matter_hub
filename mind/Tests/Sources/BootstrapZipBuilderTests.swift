import XCTest
@testable import BootstrapKit
@testable import GraphCore

/// v1.0-alpha.6 — Locks the in-memory `BootstrapArchive` builder.
/// Walks the `[String: Data]` map directly so we never touch disk
/// from the test suite.
final class BootstrapZipBuilderTests: XCTestCase {

    private func sampleBlueprint(
        admin: Bool = false,
        blog: Bool = false,
        i18n: Bool = false,
        stripe: Bool = false
    ) -> BootstrapBlueprint {
        BootstrapBlueprint(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            projectName: "AZ Construction",
            slug: "az-construction",
            host: "www.azconstruction.fr",
            githubOrg: "MaestroMed",
            stack: .nextjs,
            primaryColor: "#1F6FEB",
            contractType: .retainer,
            monthlyRecurringRevenueEUR: 290,
            includeAdminBackoffice: admin,
            includeBlogMDX: blog,
            includeI18nFREN: i18n,
            includeStripe: stripe,
            generatedAt: Date(timeIntervalSince1970: 1_747_699_200)
        )
    }

    func test_archive_includesIndexFiles_packageJSON_README_envExample() {
        let archive = BootstrapZipBuilder.archive(for: sampleBlueprint())
        XCTAssertNotNil(archive.files["README.md"],
                        "Archive contract: README.md is mandatory")
        XCTAssertNotNil(archive.files["package.json"])
        XCTAssertNotNil(archive.files[".env.example"])
        XCTAssertNotNil(archive.files["src/app/layout.tsx"])
    }

    func test_archive_sizeIsUnderReasonableCeiling() {
        let archive = BootstrapZipBuilder.archive(for: sampleBlueprint(
            admin: true, blog: true, i18n: true, stripe: true
        ))
        XCTAssertLessThan(archive.totalBytes, 200_000,
                          "Archive must stay under 200 KB — pure text scaffold should be << that")
    }

    func test_archive_paths_useForwardSlashes() {
        let archive = BootstrapZipBuilder.archive(for: sampleBlueprint())
        for path in archive.sortedFilePaths {
            XCTAssertFalse(path.contains("\\"),
                           "Path \(path) must use forward slashes — never backslashes")
        }
    }

    func test_archive_deterministic_forSameBlueprint() {
        let bp = sampleBlueprint(admin: true, blog: true)
        let a = BootstrapZipBuilder.archive(for: bp)
        let b = BootstrapZipBuilder.archive(for: bp)
        XCTAssertEqual(a.sortedFilePaths, b.sortedFilePaths,
                       "Building the same blueprint twice must produce the same file paths")
        for path in a.sortedFilePaths {
            XCTAssertEqual(a.files[path], b.files[path],
                           "File bytes must be identical for path \(path) across two runs")
        }
        XCTAssertEqual(a.folderSlug, b.folderSlug,
                       "folderSlug must be deterministic for the same blueprint")
    }
}
