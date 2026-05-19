import XCTest
import SwiftUI
@testable import DesignSystem

/// Coverage for the pure markdown → AttributedString helper that
/// powers the v0.5 Note editor's blur-to-render preview. Each test
/// exercises one of the five primitives in the v0.5 acceptance
/// criteria (`**bold**`, `*italic*`, `# heading`, `## sub-heading`,
/// `- list`, `[link](url)`) so a regression in the rendering pipeline
/// trips a targeted, named failure rather than a generic snapshot diff.
final class MarkdownRenderingTests: XCTestCase {

    // MARK: - Bold + italic round-trip

    func testRendersBoldAsNonEmptyAttributedString() {
        let attributed = MarkdownRenderer.attributedString(from: "**bold word**")
        XCTAssertFalse(plainText(of: attributed).isEmpty)
        XCTAssertTrue(plainText(of: attributed).contains("bold word"))
        XCTAssertTrue(
            hasBoldRun(in: attributed),
            "Expected at least one bold run after rendering `**bold word**`."
        )
    }

    func testRendersItalicAsNonEmptyAttributedString() {
        let attributed = MarkdownRenderer.attributedString(from: "*emphasised*")
        XCTAssertFalse(plainText(of: attributed).isEmpty)
        XCTAssertTrue(plainText(of: attributed).contains("emphasised"))
        XCTAssertTrue(
            hasItalicRun(in: attributed),
            "Expected at least one italic run after rendering `*emphasised*`."
        )
    }

    // MARK: - Headings carry the header presentation intent and a
    // monotonically decreasing point size from level 1 → 6.

    func testRendersHeadingWithHeaderPresentationIntent() {
        let heading = MarkdownRenderer.attributedString(from: "# Bonjour")
        XCTAssertTrue(
            MarkdownRenderer.containsHeader(level: 1, in: heading),
            "Expected a level-1 header presentation intent for `# Bonjour`."
        )
    }

    func testRendersSubHeadingWithLevelTwoIntent() {
        let subHeading = MarkdownRenderer.attributedString(from: "## Sous-titre")
        XCTAssertTrue(
            MarkdownRenderer.containsHeader(level: 2, in: subHeading),
            "Expected a level-2 header presentation intent for `## Sous-titre`."
        )
    }

    func testHeadingPointSizesMonotonicallyDecrease() {
        let sizes = (1...6).map { MarkdownRenderer.headerPointSize(for: $0) }
        for (idx, size) in sizes.enumerated() where idx > 0 {
            XCTAssertLessThanOrEqual(
                size,
                sizes[idx - 1],
                "Heading level \(idx + 1) (\(size)pt) should be ≤ level \(idx) (\(sizes[idx - 1])pt)."
            )
        }
        XCTAssertGreaterThan(
            sizes.first ?? 0,
            sizes.last ?? 0,
            "Level 1 should be visibly larger than level 6."
        )
    }

    // MARK: - Lists

    func testRendersBulletListItem() {
        let attributed = MarkdownRenderer.attributedString(from: "- premier point")
        XCTAssertTrue(
            plainText(of: attributed).contains("premier point"),
            "Bullet text should survive markdown parsing."
        )
        XCTAssertTrue(
            hasListItemRun(in: attributed),
            "Expected a list-item presentation intent for `- premier point`."
        )
    }

    // MARK: - Links

    func testRendersLinkWithURLAttribute() {
        let attributed = MarkdownRenderer.attributedString(
            from: "Voir [Apple](https://apple.com)"
        )
        let urls = attributed.runs.compactMap { $0.link }
        XCTAssertEqual(
            urls.first?.absoluteString,
            "https://apple.com",
            "Expected the rendered link to carry the URL via the .link attribute."
        )
    }

    // MARK: - Helpers

    private func plainText(of attributed: AttributedString) -> String {
        String(attributed.characters)
    }

    private func hasBoldRun(in attributed: AttributedString) -> Bool {
        for run in attributed.runs {
            if let intent = run.inlinePresentationIntent,
               intent.contains(.stronglyEmphasized) {
                return true
            }
        }
        return false
    }

    private func hasItalicRun(in attributed: AttributedString) -> Bool {
        for run in attributed.runs {
            if let intent = run.inlinePresentationIntent,
               intent.contains(.emphasized) {
                return true
            }
        }
        return false
    }

    private func hasListItemRun(in attributed: AttributedString) -> Bool {
        for run in attributed.runs {
            guard let intent = run.presentationIntent else { continue }
            for component in intent.components {
                if case .listItem = component.kind {
                    return true
                }
            }
        }
        return false
    }
}
