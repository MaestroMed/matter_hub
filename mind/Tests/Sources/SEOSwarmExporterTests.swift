import XCTest
@testable import SwarmKit

/// v1.0-alpha.7 — Locks the pure SEO Swarm exporter contract. Every
/// test runs against in-memory `SwarmPage` fixtures; no disk I/O.
final class SEOSwarmExporterTests: XCTestCase {

    // MARK: - Fixtures

    private func page(service: String, zoneSlug: String) -> SwarmPage {
        SwarmPage(
            serviceSlug: service,
            zoneSlug: zoneSlug,
            route: "/\(service)/\(zoneSlug)",
            title: "\(service.capitalized) \(zoneSlug.capitalized) — Test",
            metaDescription: "Test meta description for \(service) at \(zoneSlug).",
            h1: "\(service.capitalized) à \(zoneSlug.capitalized)",
            bodyMarkdown: "## Intro\n\nFrench body text for \(service).",
            jsonLD: "{\"@context\":\"https://schema.org\",\"@type\":\"LocalBusiness\"}"
        )
    }

    // MARK: - Output shape

    /// One file per page in the output dictionary. The wizard sells
    /// the user on "N pages générées" — the export must deliver N.
    func test_export_outputsOneFilePerPage() {
        let pages = [
            page(service: "verriere", zoneSlug: "puteaux"),
            page(service: "verriere", zoneSlug: "neuilly-sur-seine"),
            page(service: "escalier", zoneSlug: "puteaux"),
        ]
        let output = SEOSwarmExporter.nextJSAppRouter(pages: pages)
        XCTAssertEqual(output.count, 3)
    }

    /// File paths use POSIX forward slashes regardless of platform.
    /// The downstream ZIP writer iterates these paths verbatim.
    func test_export_pathsUseForwardSlashes() {
        let pages = [page(service: "verriere", zoneSlug: "puteaux")]
        let output = SEOSwarmExporter.nextJSAppRouter(pages: pages)
        for key in output.keys {
            XCTAssertFalse(key.contains("\\"), "Path should not contain backslash: \(key)")
            XCTAssertTrue(key.contains("/"), "Path should use forward slashes: \(key)")
        }
    }

    /// Each rendered file must contain the page route so the
    /// canonical URL anchor lands correctly.
    func test_export_containsRoute() {
        let pages = [page(service: "verriere", zoneSlug: "puteaux")]
        let output = SEOSwarmExporter.nextJSAppRouter(pages: pages)
        let key = "src/app/verriere/puteaux/page.tsx"
        XCTAssertNotNil(output[key])
        let body = String(data: output[key]!, encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("/verriere/puteaux"))
    }

    /// Each rendered file must embed the JSON-LD payload as a
    /// `dangerouslySetInnerHTML` script tag.
    func test_export_containsJSONLD() {
        let pages = [page(service: "verriere", zoneSlug: "puteaux")]
        let output = SEOSwarmExporter.nextJSAppRouter(pages: pages)
        let key = "src/app/verriere/puteaux/page.tsx"
        let body = String(data: output[key]!, encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("application/ld+json"))
        XCTAssertTrue(body.contains("LocalBusiness"))
    }

    /// Each rendered file must include the markdown body somewhere
    /// in the output (escaped through `jsString`). Locks the round-
    /// trip through the template.
    func test_export_containsMarkdownBody() {
        let pages = [page(service: "verriere", zoneSlug: "puteaux")]
        let output = SEOSwarmExporter.nextJSAppRouter(pages: pages)
        let key = "src/app/verriere/puteaux/page.tsx"
        let body = String(data: output[key]!, encoding: .utf8) ?? ""
        // The body markdown's "## Intro" header is escaped through
        // jsString → backslash-n separators, but the literal "Intro"
        // text survives because jsString only escapes the structural
        // characters.
        XCTAssertTrue(body.contains("Intro"))
        XCTAssertTrue(body.contains("French body text"))
    }

    /// Same input → same output. Lets a future "re-export" CTA hit
    /// a cache without surprising the user.
    func test_export_isDeterministic() {
        let pages = [
            page(service: "verriere", zoneSlug: "puteaux"),
            page(service: "escalier", zoneSlug: "neuilly-sur-seine"),
        ]
        let outputA = SEOSwarmExporter.nextJSAppRouter(pages: pages)
        let outputB = SEOSwarmExporter.nextJSAppRouter(pages: pages)
        XCTAssertEqual(outputA, outputB)
    }
}
