import Foundation
import AuditKit

/// Pure functions that turn an `AuditReport.QuickWin` into the GraphQL
/// `issueCreate` input dictionary the Linear API expects.
///
/// Why pure?
/// ---------
/// Keeps the wire-level mapping fully testable from `MINDTests` without
/// ever hitting the network. The `LinearClient` actor wraps these with
/// a `URLSession` GraphQL call; every test on the input shape stays
/// here.
///
/// Linear API reference
/// --------------------
/// - Endpoint: `POST https://api.linear.app/graphql`, header
///   `Authorization: <token>` (personal API key, no "Bearer " prefix
///   per Linear's docs).
/// - Mutation: `issueCreate(input: IssueCreateInput!) { success issue { id identifier url } }`
/// - `IssueCreateInput` fields used here:
///     - `title: String!` — the QuickWin title
///     - `description: String` — markdown body assembled from QW detail
///       + estimated effort. Linear renders this as Markdown.
///     - `teamId: String!` — the Settings-selected team UUID
///     - `priority: Int` — 0=No priority, 1=Urgent, 2=High, 3=Medium,
///       4=Low. We map `impact.high → 1`, `medium → 2`, `low → 3` so a
///       Quick Win labelled "high impact" lands as Urgent in Linear's
///       triage view (most visible). Mehdi can re-prioritise later.
///     - `labelIds`: omitted in v0.12 — labels are tenant-scoped (each
///       Linear workspace defines its own) and we don't crawl them
///       client-side yet. v0.12.1 can add a label picker the same way
///       teams are picked.
public enum LinearIssueBuilder {

    /// Fallback title surfaced when the QuickWin's title is empty after
    /// whitespace trimming. Empty titles are an invalid input on
    /// Linear's side — the API would respond with a 400 — so we
    /// substitute a descriptive fallback rather than failing the
    /// bulk push for one bad row.
    static let fallbackTitle: String = "MIND Quick Win"

    /// Builds the `input` portion of an `issueCreate` mutation for one
    /// QuickWin. Returns a plain `[String: Any]` so callers can hand
    /// it to `JSONSerialization` (the actor doesn't need a Codable
    /// round-trip and keeping the shape as a dict makes the assertions
    /// in `LinearIssueBuilderTests` trivial — no decoding required).
    ///
    /// Example output:
    /// ```
    /// [
    ///   "title": "Activer HSTS",
    ///   "description": "Activer le header HSTS pour bloquer …\n\n_Effort estimé : 1j_",
    ///   "teamId": "team_abc123",
    ///   "priority": 1
    /// ]
    /// ```
    public static func issueInput(
        for win: AuditReport.QuickWin,
        teamID: String
    ) -> [String: Any] {
        var input: [String: Any] = [:]

        input["title"] = sanitizedTitle(from: win.title)
        input["description"] = description(for: win)
        input["teamId"] = teamID
        input["priority"] = priority(for: win.impact)

        return input
    }

    // MARK: - Field mappers

    /// Trims whitespace, falls back to a non-empty default when the
    /// QuickWin title is blank, and leaves the rest of the string
    /// untouched. GraphQL escaping is handled by `JSONSerialization`
    /// downstream — special characters (quotes, newlines, backslashes,
    /// emojis) survive the dictionary trip without manual escaping.
    static func sanitizedTitle(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallbackTitle : trimmed
    }

    /// Markdown body that surfaces the QW detail + the estimated
    /// effort. The italic "Effort estimé : Xj" footer keeps the
    /// information atomic in Linear's UI without polluting the title.
    static func description(for win: AuditReport.QuickWin) -> String {
        let detail = win.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let effort = formatEffort(win.effortDays)
        if detail.isEmpty {
            return "_Effort estimé : \(effort)_"
        }
        return "\(detail)\n\n_Effort estimé : \(effort)_"
    }

    /// Maps the QuickWin impact onto Linear's priority enum. Linear's
    /// numeric scale is fixed by the API: 0=None, 1=Urgent, 2=High,
    /// 3=Medium, 4=Low. We compress MIND's three-band impact onto
    /// Urgent/High/Medium so the bulk push lands the most-impactful
    /// rows at the top of Linear's "Active" view by default.
    public static func priority(for impact: AuditReport.QuickWin.Impact) -> Int {
        switch impact {
        case .high:   return 1   // Urgent
        case .medium: return 2   // High
        case .low:    return 3   // Medium
        }
    }

    // MARK: - Formatting

    /// Mirrors the human-readable effort surfaced in the AuditSheet
    /// QW card. 0.5d → "4h", 1d → "1j", 1.5d → "1.5j", 2d → "2j".
    static func formatEffort(_ days: Double) -> String {
        if days < 1 {
            return "\(Int(days * 8))h"
        }
        let asInt = Int(days.rounded())
        return Double(asInt) == days ? "\(asInt)j" : String(format: "%.1fj", days)
    }
}
