import Foundation
import AuditKit

/// Pure function that turns an `AuditReport` into the JSON payload
/// `POST https://api.notion.com/v1/pages` expects.
///
/// Why pure?
/// ---------
/// Keeps the serialisation fully testable from `MINDTests` without ever
/// hitting the network. The `NotionClient` actor wraps this with a
/// `URLSession` call; every test on the body shape stays here.
///
/// Notion API reference
/// --------------------
/// - Endpoint: `POST /v1/pages`, header `Notion-Version: 2022-06-28`.
/// - Top-level body fields used here:
///     - `parent: { database_id: <id> }` — anchors the page under the
///       configured database. The database must be shared with the
///       integration on the Notion side; the API rejects the call with
///       a 404 otherwise (handled in `NotionClient.createAuditPage`).
///     - `properties` — must include the database's title property.
///       Notion stores the title in a property named "Name" by default
///       when a database is created in the UI; we always set "Name"
///       and add a couple of secondary props ("Score", "Persona")
///       which the database may or may not have. Notion ignores
///       properties that don't exist on the target database, so
///       posting them is safe even when the schema is bare.
///     - `children` — the page body as a list of block objects. Notion
///       caps a single page-creation request at 100 children blocks.
///       The audit report fits comfortably under that cap (heading +
///       synthesis paragraphs + 3 bulleted lists ≈ 25-40 blocks).
public enum NotionPageBuilder {

    /// Notion text rich-text strings have a hard 2000-char cap per
    /// element. Long synthesis paragraphs get chunked at this
    /// boundary by `paragraphBlocks(from:)`.
    static let richTextCharLimit: Int = 2000

    /// Builds the JSON dictionary for `POST /v1/pages`. Returns a plain
    /// `[String: Any]` so callers can hand it to `JSONSerialization`
    /// (the actor doesn't need a Codable round-trip and keeping the
    /// shape as a dict makes the assertions in
    /// `NotionPageBuilderTests` trivial — no decoding required).
    public static func buildPagePayload(
        for report: AuditReport,
        databaseID: String
    ) -> [String: Any] {
        var payload: [String: Any] = [:]
        payload["parent"] = ["database_id": databaseID]
        payload["properties"] = buildProperties(for: report)
        payload["children"] = buildChildren(for: report)
        return payload
    }

    // MARK: - Properties

    /// Title + a couple of secondary props. Notion ignores unknown
    /// property names on the target database, so the call still
    /// succeeds even if the user's database only has the default
    /// title column. The score is stored as a `rich_text` (rather
    /// than `number`) so a freshly-created database with no
    /// "Score" column still surfaces the value as a sub-title-style
    /// row inline.
    static func buildProperties(for report: AuditReport) -> [String: Any] {
        let title = report.client.displayName
        var properties: [String: Any] = [
            "Name": [
                "title": [
                    ["text": ["content": title]]
                ]
            ],
            "Score": [
                "rich_text": [
                    ["text": ["content": "\(report.scoring.overall) / 100"]]
                ]
            ],
            "Persona": [
                "select": ["name": report.persona.label]
            ],
        ]

        // URL goes in too so the Notion row links back to the audited
        // site without the user having to copy-paste. Same "unknown
        // properties are silently dropped" contract applies.
        properties["URL"] = ["url": report.client.url.absoluteString]

        return properties
    }

    // MARK: - Children blocks

    static func buildChildren(for report: AuditReport) -> [[String: Any]] {
        var blocks: [[String: Any]] = []

        // Header: client URL + generated timestamp as a callout so
        // the page top reads like a one-line summary.
        blocks.append(calloutBlock(
            emoji: "🧠",
            text: "Audit MIND — \(formattedDate(report.generatedAt))"
        ))

        // Synthesis — long-form markdown. We split on blank lines so
        // each paragraph becomes its own Notion paragraph block, and
        // every paragraph longer than `richTextCharLimit` is chunked
        // into multiple rich-text spans inside the same block to stay
        // under the Notion per-span 2000-char ceiling.
        blocks.append(headingTwoBlock("Synthèse"))
        blocks.append(contentsOf: paragraphBlocks(from: report.synthesis))

        // Quick wins — heading_2 + bulleted list (one item per win).
        if !report.quickWins.isEmpty {
            blocks.append(headingTwoBlock("Quick wins"))
            for win in report.quickWins {
                let line = "\(win.title) — \(formatEffort(win.effortDays)), impact \(win.impact.rawValue). \(win.detail)"
                blocks.append(bulletedItemBlock(line))
            }
        }

        // Strategic bets — heading_2 + bulleted list.
        if !report.strategicBets.isEmpty {
            blocks.append(headingTwoBlock("Paris stratégiques"))
            for bet in report.strategicBets {
                let line = "\(bet.title) — \(bet.durationMonths) mois, €\(bet.budgetMinEUR / 1000)k–€\(bet.budgetMaxEUR / 1000)k. \(bet.detail)"
                blocks.append(bulletedItemBlock(line))
            }
        }

        // Hidden risks — heading_2 + bulleted list. Severity goes
        // into the bullet copy so the page stays readable without
        // requiring a multi-column Notion view.
        if !report.hiddenRisks.isEmpty {
            blocks.append(headingTwoBlock("Risques cachés"))
            for risk in report.hiddenRisks {
                let line = "[\(risk.severity.rawValue.uppercased())] \(risk.title) — \(risk.detail)"
                blocks.append(bulletedItemBlock(line))
            }
        }

        // Pitch — full markdown body, same chunking as synthesis.
        blocks.append(headingTwoBlock("Pitch prêt à envoyer"))
        blocks.append(contentsOf: paragraphBlocks(from: report.pitch))

        return blocks
    }

    // MARK: - Block builders (small helpers)

    static func headingTwoBlock(_ text: String) -> [String: Any] {
        [
            "object": "block",
            "type": "heading_2",
            "heading_2": [
                "rich_text": [
                    ["type": "text", "text": ["content": text]]
                ]
            ],
        ]
    }

    static func calloutBlock(emoji: String, text: String) -> [String: Any] {
        [
            "object": "block",
            "type": "callout",
            "callout": [
                "icon": ["type": "emoji", "emoji": emoji],
                "rich_text": [
                    ["type": "text", "text": ["content": text]]
                ],
            ],
        ]
    }

    static func bulletedItemBlock(_ text: String) -> [String: Any] {
        [
            "object": "block",
            "type": "bulleted_list_item",
            "bulleted_list_item": [
                "rich_text": richTextSpans(from: text),
            ],
        ]
    }

    static func paragraphBlock(_ spans: [[String: Any]]) -> [String: Any] {
        [
            "object": "block",
            "type": "paragraph",
            "paragraph": [
                "rich_text": spans,
            ],
        ]
    }

    /// One Notion paragraph block per non-empty line / block of
    /// markdown, with rich-text chunked to respect the 2000-char cap.
    /// The split on "\n\n" matches how `AuditExporter.markdown(from:)`
    /// composes the synthesis sections, so the resulting Notion page
    /// reads the same way as the Markdown export.
    static func paragraphBlocks(from markdown: String) -> [[String: Any]] {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            // Always emit at least one paragraph so the page never
            // ends on a heading with no body — that looks broken in
            // Notion.
            return [paragraphBlock([["type": "text", "text": ["content": " "]]])]
        }
        let paragraphs = trimmed.components(separatedBy: "\n\n")
        return paragraphs.compactMap { raw in
            let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return nil }
            return paragraphBlock(richTextSpans(from: cleaned))
        }
    }

    /// Chunks `text` into Notion rich-text spans of at most
    /// `richTextCharLimit` characters each. Notion concatenates them
    /// inside the same block so the visible paragraph remains a
    /// single line — only the wire-level rich-text array is split.
    static func richTextSpans(from text: String) -> [[String: Any]] {
        guard text.count > richTextCharLimit else {
            return [["type": "text", "text": ["content": text]]]
        }
        var spans: [[String: Any]] = []
        var remaining = text[...]
        while !remaining.isEmpty {
            let endIndex = remaining.index(
                remaining.startIndex,
                offsetBy: min(richTextCharLimit, remaining.count)
            )
            let chunk = String(remaining[..<endIndex])
            spans.append(["type": "text", "text": ["content": chunk]])
            remaining = remaining[endIndex...]
        }
        return spans
    }

    // MARK: - Formatting

    static func formattedDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
    }

    static func formatEffort(_ days: Double) -> String {
        if days < 1 {
            return "\(Int(days * 8))h"
        }
        let asInt = Int(days.rounded())
        return Double(asInt) == days ? "\(asInt)j" : String(format: "%.1fj", days)
    }
}
