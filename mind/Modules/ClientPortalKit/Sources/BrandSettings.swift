import Foundation

/// Brand-side metadata baked into a `ClientPortalArchive` when it's
/// generated — the consultant's name, accent colour, contact info and
/// (optionally) a portrait the pitch section embeds inline as base64.
///
/// Lives outside the `AuditReport` because the report is the
/// *client*'s data; this struct is the *consultant*'s identity. The
/// two compose: `ClientPortalBuilder.generateSite(for: report,
/// brand: .default)` injects Mehdi's name + iris accent into the HTML
/// templates, but a future "white-label" path could swap in another
/// consultant's brand without touching the report at all.
///
/// `accentColor` is a hex string (`"#6B5DD3"`) rather than a Color
/// because the value lives in HTML strings — the framework target is
/// Foundation-only (no UIKit / SwiftUI) so the resulting `index.html`
/// renders identically on any platform the audit later ships to.
public struct BrandSettings: Sendable, Hashable {

    /// CSS hex colour pasted into gradient stops and accent strokes.
    /// Defaults to MIND iris (`#6B5DD3`), matching the in-app Liquid
    /// Glass palette so the portal feels like a continuation of the
    /// MIND app screenshots the prospect was just sent.
    public let accentColor: String

    /// Web-safe font-family name used in the inline `<style>` block.
    /// Falls back through Apple's system stack so iOS / macOS readers
    /// see the same SF Pro rendering as a native MIND screen, then to
    /// Inter for Linux/Windows clients via the Google Fonts CDN
    /// `<link rel="preconnect">` the template injects.
    public let font: String

    /// Free-form display name (`"Mehdi Nafaa"`) — rendered in the
    /// hero subtitle, the pitch byline and the footer.
    public let consultantName: String

    /// Optional contact email. When set, the contact section CTA
    /// renders a `mailto:` button alongside the Calendly link.
    public let consultantEmail: String?

    /// Optional consultant portrait. When set, the pitch section
    /// embeds the image as a `data:image/jpeg;base64,…` URL so the
    /// resulting `index.html` stays single-file (no `<img src=…>`
    /// pointing at a sibling asset that could 404 after the Vercel
    /// drop). `nil` = the pitch section uses initials in a tinted
    /// circle as a fallback.
    public let consultantPhotoData: Data?

    /// Role title shown under the consultant's name in the pitch +
    /// footer. Mehdi's default ("Senior Digital Consultant") is set
    /// in English deliberately — the consumer of the portal is a
    /// client decision-maker, not the consultant.
    public let consultantTitle: String

    /// Optional Calendly / scheduling URL. When set, the contact
    /// section renders the primary "Réserver un appel" CTA.
    public let calendlyURL: String?

    public init(
        accentColor: String = "#6B5DD3",
        font: String = "-apple-system, BlinkMacSystemFont, 'SF Pro Display', 'SF Pro Text', Inter, system-ui, sans-serif",
        consultantName: String = "Mehdi Nafaa",
        consultantEmail: String? = nil,
        consultantPhotoData: Data? = nil,
        consultantTitle: String = "Senior Digital Consultant",
        calendlyURL: String? = nil
    ) {
        self.accentColor = accentColor
        self.font = font
        self.consultantName = consultantName
        self.consultantEmail = consultantEmail
        self.consultantPhotoData = consultantPhotoData
        self.consultantTitle = consultantTitle
        self.calendlyURL = calendlyURL
    }

    /// Default MIND-branded settings — iris accent, Apple-system font
    /// stack, Mehdi Nafaa byline, no portrait, no Calendly URL.
    public static let `default` = BrandSettings()

    /// Two-letter uppercase initials, used by the pitch section's
    /// no-photo fallback (`MN` for "Mehdi Nafaa", `S` for single-word
    /// names, falling back to `M` if the name is empty).
    public var consultantInitials: String {
        let parts = consultantName
            .split(separator: " ")
            .filter { !$0.isEmpty }
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        } else if let only = parts.first {
            return String(only.prefix(1)).uppercased()
        } else {
            return "M"
        }
    }
}
