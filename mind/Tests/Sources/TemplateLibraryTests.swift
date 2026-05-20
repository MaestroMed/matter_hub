import XCTest
@testable import BootstrapKit
@testable import GraphCore

/// v1.0-alpha.6 — Locks the pure file-template strings against
/// regressions. The scaffolded site has to compile out of the box,
/// so the most load-bearing properties (valid JSON, correct env
/// var names, default-exported components) are asserted here.
final class TemplateLibraryTests: XCTestCase {

    // MARK: - package.json

    func test_packageJSON_isValidJSON_forNextJSStack() throws {
        let body = TemplateLibrary.packageJSON(
            slug: "az-construction",
            stack: .nextjs,
            includeAdmin: false,
            includeBlog: false,
            includeStripe: false
        )
        let data = Data(body.utf8)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json, "package.json must parse as valid JSON")
        XCTAssertEqual(json?["name"] as? String, "az-construction",
                       "package.json name must match the slug")
    }

    func test_packageJSON_alwaysIncludesMindLeadWebhook() {
        let body = TemplateLibrary.packageJSON(
            slug: "acme",
            stack: .nextjs,
            includeAdmin: false,
            includeBlog: false,
            includeStripe: false
        )
        XCTAssertTrue(body.contains("@mind/lead-webhook"),
                      "Every package.json must include @mind/lead-webhook")
    }

    // MARK: - layout.tsx

    func test_layoutTSX_exportsDefaultFunction_andCarriesHost() {
        let body = TemplateLibrary.layoutTSX(
            host: "www.azconstruction.fr",
            projectName: "AZ Construction",
            primaryColor: "#1F6FEB"
        )
        XCTAssertTrue(body.contains("export default function RootLayout"),
                      "layout.tsx must export a default RootLayout")
        XCTAssertTrue(body.contains("https://www.azconstruction.fr"),
                      "layout.tsx must hardcode the metadataBase URL with the host")
        XCTAssertTrue(body.contains("themeColor: '#1F6FEB'"),
                      "viewport must carry the blueprint primary color")
    }

    // MARK: - contact/route.ts

    func test_contactRoute_usesZod_andResend_andSendLeadToMIND() {
        let body = TemplateLibrary.contactRouteTS()
        XCTAssertTrue(body.contains("import { z } from 'zod'"),
                      "Contact route must validate input via Zod")
        XCTAssertTrue(body.contains("import { Resend } from 'resend'"),
                      "Contact route must use Resend for transactional email")
        XCTAssertTrue(body.contains("sendLeadToMIND("),
                      "Contact route must forward leads to MIND before emailing")
    }

    // MARK: - vercel.json

    func test_vercelJSON_isValidJSON_andCarriesSecurityHeaders() throws {
        let body = TemplateLibrary.vercelJSON()
        let data = Data(body.utf8)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json, "vercel.json must parse as valid JSON")
        XCTAssertTrue(body.contains("Strict-Transport-Security"),
                      "vercel.json must ship the HSTS header")
        XCTAssertTrue(body.contains("X-Frame-Options"),
                      "vercel.json must ship the X-Frame-Options header")
        XCTAssertTrue(body.contains("\"cdg1\""),
                      "vercel.json must pin Paris (cdg1) region for Numelite clients")
    }

    // MARK: - .env.example

    func test_envExample_listsEveryRequiredVar() {
        let body = TemplateLibrary.envExample(includeStripe: false)
        for key in [
            "RESEND_API_KEY",
            "DATABASE_URL",
            "MIND_PROJECT_ID",
            "MIND_WEBHOOK_URL",
            "MIND_WEBHOOK_SECRET",
            "NEXT_PUBLIC_PLAUSIBLE_DOMAIN",
        ] {
            XCTAssertTrue(body.contains(key),
                          ".env.example must list \(key) so the operator can't deploy with a missing secret")
        }
    }

    func test_envExample_includesStripeKeys_ONLY_whenStripeBundleIsOn() {
        let off = TemplateLibrary.envExample(includeStripe: false)
        let on  = TemplateLibrary.envExample(includeStripe: true)
        XCTAssertFalse(off.contains("STRIPE_SECRET_KEY"),
                       "Stripe env keys must NOT appear when the bundle is off")
        XCTAssertTrue(on.contains("STRIPE_SECRET_KEY"))
        XCTAssertTrue(on.contains("STRIPE_WEBHOOK_SECRET"))
    }

    // MARK: - robots / sitemap

    func test_robots_pointsAtHostsSitemap() {
        let body = TemplateLibrary.robotsTS(host: "www.acme.fr")
        XCTAssertTrue(body.contains("https://www.acme.fr/sitemap.xml"),
                      "robots.ts must point at the host's sitemap URL")
    }
}
