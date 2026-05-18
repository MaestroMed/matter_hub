import Foundation

/// Detects whether the site shows a cookie consent banner and which
/// vendor powers it. Direct signal for GDPR / e-Privacy maturity.
public enum CookieBannerProbe {
    private static let providers: [(needle: String, label: String)] = [
        ("cookiebot",           "Cookiebot"),
        ("axeptio",             "Axeptio"),
        ("didomi",              "Didomi"),
        ("onetrust",            "OneTrust"),
        ("optanon",             "OneTrust"),
        ("tarteaucitron",       "tarteaucitron.js"),
        ("cookieyes",           "CookieYes"),
        ("usercentrics",        "Usercentrics"),
        ("cookieconsent",       "Cookie Consent"),
        ("orejime",             "Orejime"),
        ("klaro",               "Klaro"),
        ("trustarc",            "TrustArc"),
        ("quantcast",           "Quantcast Choice"),
        ("iubenda",             "Iubenda"),
        ("hubspot/usemb",       "HubSpot CMS"),
    ]

    public static func fetch(for url: URL) async throws -> ComplianceFindings {
        let html = try await HTMLProbe.fetchLowercased(url)

        let provider = providers.first { html.contains($0.needle) }?.label
        let genericBannerHints = ["cookie-banner", "cookie_consent", "we use cookies", "nous utilisons des cookies"]
        let hasBanner = provider != nil || genericBannerHints.contains { html.contains($0) }

        let hasPrivacyLink = matchesAnyPath(in: html, paths: [
            "/privacy", "/privacy-policy", "/confidentialite", "/politique-de-confidentialite", "/datenschutz"
        ])
        let hasTermsLink = matchesAnyPath(in: html, paths: [
            "/terms", "/terms-of-service", "/tos", "/cgu", "/conditions-generales", "/mentions-legales", "/legal"
        ])

        return ComplianceFindings(
            hasCookieBanner: hasBanner,
            cookieProvider: provider,
            hasPrivacyLink: hasPrivacyLink,
            hasTermsLink: hasTermsLink
        )
    }

    private static func matchesAnyPath(in html: String, paths: [String]) -> Bool {
        for path in paths {
            if html.contains("href=\"\(path)\"")
                || html.contains("href='\(path)'")
                || html.contains("\(path)\"")
                || html.contains("\(path)'") {
                return true
            }
        }
        return false
    }
}
