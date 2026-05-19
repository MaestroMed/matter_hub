import XCTest
@testable import AuditKit
@testable import LinearKit

/// Pure tests for `LinearIssueBuilder.issueInput(for:teamID:)`.
///
/// Why pure?
/// ---------
/// The builder produces a `[String: Any]` matching the GraphQL
/// `IssueCreateInput!` payload. Every test asserts on the dict
/// directly — no `URLSession`, no `JSONEncoder`, no mocked Linear
/// server. The actor that wraps the builder is exercised end-to-end
/// from the AuditSheet "Push to Linear" rows on a real device.
///
/// What's locked here
/// ------------------
/// - Title surfaces the QuickWin title (trimmed)
/// - Empty / whitespace title falls back to a non-empty default so
///   the GraphQL call doesn't bounce with a 400
/// - teamID is forwarded verbatim — the picker hands the same UUID
///   the bulk push uses
/// - Priority maps onto Linear's Urgent/High/Medium enum based on the
///   QuickWin impact band (high → 1, medium → 2, low → 3)
/// - Description includes the QW detail + the estimated-effort
///   markdown footer
/// - Special characters (quotes, newlines, emojis) survive the dict
///   trip — JSONSerialization handles the GraphQL string escaping
final class LinearIssueBuilderTests: XCTestCase {

    // MARK: - Title

    func testTitleEqualsQuickWinTitle() {
        let win = AuditReport.QuickWin(
            title: "Activer HSTS",
            detail: "Header HSTS manquant",
            effortDays: 0.5,
            impact: .high
        )
        let input = LinearIssueBuilder.issueInput(for: win, teamID: "team_abc")
        XCTAssertEqual(input["title"] as? String, "Activer HSTS")
    }

    func testEmptyTitleFallsBackToNonEmptyDefault() {
        let win = AuditReport.QuickWin(
            title: "   ",
            detail: "Something",
            effortDays: 1,
            impact: .medium
        )
        let input = LinearIssueBuilder.issueInput(for: win, teamID: "team_abc")
        let title = input["title"] as? String
        XCTAssertNotNil(title)
        XCTAssertFalse(title?.isEmpty ?? true,
                       "Empty title must fall back to a non-empty default")
        XCTAssertEqual(title, "MIND Quick Win")
    }

    func testTitleSpecialCharactersAreForwardedVerbatim() {
        // GraphQL escaping is handled downstream by `JSONSerialization`
        // — the builder must preserve special characters as-is so the
        // serialiser sees them unmodified.
        let win = AuditReport.QuickWin(
            title: "Fix \"big\" issue 🐛\nNow",
            detail: "Detail",
            effortDays: 1,
            impact: .high
        )
        let input = LinearIssueBuilder.issueInput(for: win, teamID: "team_abc")
        XCTAssertEqual(input["title"] as? String, "Fix \"big\" issue 🐛\nNow")
    }

    // MARK: - teamID forwarding

    func testTeamIDIsForwardedVerbatim() {
        let win = AuditReport.QuickWin(
            title: "X",
            detail: "Y",
            effortDays: 1,
            impact: .high
        )
        let input = LinearIssueBuilder.issueInput(for: win, teamID: "team_unique_42")
        XCTAssertEqual(input["teamId"] as? String, "team_unique_42")
    }

    // MARK: - Priority mapping

    func testPriorityMapsHighImpactToUrgent() {
        XCTAssertEqual(LinearIssueBuilder.priority(for: .high), 1,
                       "high impact must map to Linear priority 1 (Urgent)")
    }

    func testPriorityMapsMediumImpactToHigh() {
        XCTAssertEqual(LinearIssueBuilder.priority(for: .medium), 2,
                       "medium impact must map to Linear priority 2 (High)")
    }

    func testPriorityMapsLowImpactToMedium() {
        XCTAssertEqual(LinearIssueBuilder.priority(for: .low), 3,
                       "low impact must map to Linear priority 3 (Medium)")
    }

    func testIssueInputPriorityReflectsImpact() {
        let high = AuditReport.QuickWin(title: "A", detail: "X", effortDays: 1, impact: .high)
        let medium = AuditReport.QuickWin(title: "B", detail: "X", effortDays: 1, impact: .medium)
        let low = AuditReport.QuickWin(title: "C", detail: "X", effortDays: 1, impact: .low)

        XCTAssertEqual(LinearIssueBuilder.issueInput(for: high, teamID: "t")["priority"] as? Int, 1)
        XCTAssertEqual(LinearIssueBuilder.issueInput(for: medium, teamID: "t")["priority"] as? Int, 2)
        XCTAssertEqual(LinearIssueBuilder.issueInput(for: low, teamID: "t")["priority"] as? Int, 3)
    }

    // MARK: - Description

    func testDescriptionIncludesDetailAndEffort() {
        let win = AuditReport.QuickWin(
            title: "T",
            detail: "Configure HSTS for max-age=31536000",
            effortDays: 1,
            impact: .high
        )
        let input = LinearIssueBuilder.issueInput(for: win, teamID: "t")
        let description = input["description"] as? String ?? ""

        XCTAssertTrue(description.contains("Configure HSTS for max-age=31536000"),
                      "Description must include the QuickWin detail")
        XCTAssertTrue(description.contains("1j"),
                      "Description must include the formatted effort estimate")
        XCTAssertTrue(description.contains("Effort estimé"),
                      "Description must surface the effort footer label")
    }

    func testDescriptionHandlesHalfDayEffort() {
        let win = AuditReport.QuickWin(
            title: "T",
            detail: "Tiny change",
            effortDays: 0.5,
            impact: .low
        )
        let input = LinearIssueBuilder.issueInput(for: win, teamID: "t")
        let description = input["description"] as? String ?? ""
        XCTAssertTrue(description.contains("4h"),
                      "Half-day effort must format as '4h' (0.5 * 8 hours)")
    }

    func testDescriptionWithEmptyDetailStillSurfacesEffort() {
        let win = AuditReport.QuickWin(
            title: "T",
            detail: "",
            effortDays: 2,
            impact: .medium
        )
        let input = LinearIssueBuilder.issueInput(for: win, teamID: "t")
        let description = input["description"] as? String ?? ""
        XCTAssertTrue(description.contains("2j"),
                      "Even with no detail, the effort footer must render")
    }
}
