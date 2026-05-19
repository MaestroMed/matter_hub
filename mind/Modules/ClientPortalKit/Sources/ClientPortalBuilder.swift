import Foundation
import AuditKit

/// Pure entry point: takes an `AuditReport` + `BrandSettings`, returns
/// an in-memory `ClientPortalArchive` ready to write to disk.
///
/// Everything observable from the outside is a value type:
/// - **Input**: `AuditReport` (Sendable, Codable), `BrandSettings`
///   (Sendable, value type).
/// - **Output**: `ClientPortalArchive` (Sendable, plain `[String: Data]`
///   plus a folder slug).
///
/// No FileManager, no UIKit, no telemetry sinks — that's the
/// `PortalWriter` actor's job. Keeping the builder pure means every
/// assertion in `ClientPortalBuilderTests` is a one-liner with no
/// async / no setup boilerplate.
///
/// The HTML / CSS / JS string composition is delegated to
/// `HTMLTemplates` so each helper there can be unit-tested in
/// isolation and the file boundaries map onto the ULTRAPLAN spec.
public enum ClientPortalBuilder {

    /// Hard ceiling on the total archive byte size enforced by the
    /// page-weight test. Matches the ULTRAPLAN acceptance criterion
    /// ("under the locked 200 KB ceiling") — a careless template
    /// addition that pushes the page-weight beyond budget breaks the
    /// test instead of silently bloating every generated portal.
    public static let pageWeightCeilingBytes: Int = 200_000

    /// Build the in-memory archive for the given report.
    ///
    /// Currently emits a single `index.html` file (all CSS + JS
    /// inlined, no sibling assets). A future iteration can append
    /// `assets/og.png` (pre-rendered Open Graph card), `robots.txt`,
    /// a favicon, etc. without changing the call sites — the dict
    /// shape absorbs new keys.
    public static func generateSite(
        for report: AuditReport,
        brand: BrandSettings = .default
    ) -> ClientPortalArchive {
        let html = HTMLTemplates.indexHTML(for: report, brand: brand)
        let bytes = Data(html.utf8)
        let slug = makeSlug(clientName: report.client.displayName, date: report.generatedAt)
        return ClientPortalArchive(
            files: ["index.html": bytes],
            folderSlug: slug
        )
    }

    /// Pure helper: filesystem-safe folder name like
    /// `"acme-corp-2026-05-19"`. Lower-cases ASCII, strips
    /// diacritics, collapses anything non-alphanumeric to a single
    /// dash, trims dash runs at the edges. Pure — no locale that
    /// could make the result drift between dev machines, no calendar
    /// math that flips around midnight in a different time zone.
    public static func makeSlug(clientName: String, date: Date) -> String {
        let folded = clientName
            .folding(options: .diacriticInsensitive,
                     locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        var slug = ""
        var lastWasDash = false
        for scalar in folded.unicodeScalars {
            let isAllowed = (scalar.value >= 0x30 && scalar.value <= 0x39)   // 0-9
                         || (scalar.value >= 0x61 && scalar.value <= 0x7A)   // a-z
            if isAllowed {
                slug.append(Character(scalar))
                lastWasDash = false
            } else if !lastWasDash {
                slug.append("-")
                lastWasDash = true
            }
        }
        while slug.hasPrefix("-") { slug.removeFirst() }
        while slug.hasSuffix("-") { slug.removeLast() }
        if slug.isEmpty { slug = "client" }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(slug)-\(formatter.string(from: date))"
    }
}
