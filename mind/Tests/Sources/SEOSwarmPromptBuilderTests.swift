import XCTest
@testable import SwarmKit

/// v1.0-alpha.7 — Locks the pure parts of the SEO Swarm Orchestrator
/// prompt builder. Every test runs without network access; the
/// orchestrator's network round-trip is exercised end-to-end through
/// the simulator screenshot.
final class SEOSwarmPromptBuilderTests: XCTestCase {

    // MARK: - Fixtures

    private func sampleProject() -> SwarmProjectContext {
        SwarmProjectContext(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "AZ Construction",
            host: "www.azconstruction.fr"
        )
    }

    private func sampleZone(population: Int? = 45_000) -> SwarmZone {
        SwarmZone(
            slug: "puteaux",
            displayName: "Puteaux",
            departmentCode: "92",
            population: population
        )
    }

    // MARK: - System prompt

    /// The system prompt must explicitly mention FR — every page in
    /// the swarm is in French and the persona instruction is the
    /// load-bearing thing keeping Claude from drifting to EN.
    func test_systemPrompt_mentionsFR() {
        let prompt = SEOSwarmPromptBuilder.systemPrompt()
        XCTAssertTrue(
            prompt.contains("FR") || prompt.contains("français"),
            "System prompt must mention FR or français"
        )
    }

    // MARK: - Page prompt — anchors

    /// The per-page prompt must include the project name and host so
    /// Claude grounds the LocalBusiness JSON-LD on the correct site.
    func test_pagePrompt_includesProjectIdentity() {
        let prompt = SEOSwarmPromptBuilder.pagePrompt(
            project: sampleProject(),
            service: "verriere",
            zone: sampleZone()
        )
        XCTAssertTrue(prompt.contains("AZ Construction"))
        XCTAssertTrue(prompt.contains("www.azconstruction.fr"))
    }

    /// The per-page prompt must mention the service slug + the zone
    /// display name so Claude doesn't generate a generic page.
    func test_pagePrompt_includesServiceAndZone() {
        let prompt = SEOSwarmPromptBuilder.pagePrompt(
            project: sampleProject(),
            service: "verriere",
            zone: sampleZone()
        )
        XCTAssertTrue(prompt.contains("Puteaux"))
        XCTAssertTrue(prompt.contains("92"))
        XCTAssertTrue(prompt.lowercased().contains("verriere") || prompt.contains("Verriere"))
    }

    /// The prompt must explicitly ask for JSON output. The
    /// orchestrator soft-fails on parse errors, but the contract
    /// starts here.
    func test_pagePrompt_asksForJSONOnly() {
        let prompt = SEOSwarmPromptBuilder.pagePrompt(
            project: sampleProject(),
            service: "verriere",
            zone: sampleZone()
        )
        XCTAssertTrue(prompt.contains("JSON"))
        XCTAssertTrue(prompt.contains("\"title\""))
        XCTAssertTrue(prompt.contains("\"jsonLD\""))
    }

    /// The prompt must instruct Claude to emit a `LocalBusiness`
    /// schema in the JSON-LD payload — the whole SEO swarm benefit
    /// hinges on this structured data.
    func test_pagePrompt_mentionsLocalBusinessSchema() {
        let prompt = SEOSwarmPromptBuilder.pagePrompt(
            project: sampleProject(),
            service: "verriere",
            zone: sampleZone()
        )
        XCTAssertTrue(prompt.contains("LocalBusiness"))
    }

    /// The body length contract: 1500-2500 words FR. Lock it so a
    /// future prompt edit doesn't quietly drop the lower bound.
    func test_pagePrompt_requestsWordCountRange() {
        let prompt = SEOSwarmPromptBuilder.pagePrompt(
            project: sampleProject(),
            service: "verriere",
            zone: sampleZone()
        )
        XCTAssertTrue(prompt.contains("1500"))
        XCTAssertTrue(prompt.contains("2500"))
    }

    // MARK: - Determinism + variance

    /// Same input → same output. The future "régénérer" CTA can hit a
    /// cache without surprising the user with a different prompt.
    func test_pagePrompt_isDeterministicForSameInput() {
        let project = sampleProject()
        let zone = sampleZone()
        let a = SEOSwarmPromptBuilder.pagePrompt(project: project, service: "escalier", zone: zone)
        let b = SEOSwarmPromptBuilder.pagePrompt(project: project, service: "escalier", zone: zone)
        XCTAssertEqual(a, b)
    }

    /// Different (service, zone) pairs must yield different prompts —
    /// otherwise the swarm would generate the same page twice.
    func test_pagePrompt_differsBetweenSlots() {
        let project = sampleProject()
        let zone = sampleZone()
        let otherZone = SwarmZone(slug: "neuilly-sur-seine", displayName: "Neuilly-sur-Seine", departmentCode: "92", population: 62_600)
        let promptA = SEOSwarmPromptBuilder.pagePrompt(project: project, service: "verriere", zone: zone)
        let promptB = SEOSwarmPromptBuilder.pagePrompt(project: project, service: "escalier", zone: zone)
        let promptC = SEOSwarmPromptBuilder.pagePrompt(project: project, service: "verriere", zone: otherZone)
        XCTAssertNotEqual(promptA, promptB)
        XCTAssertNotEqual(promptA, promptC)
    }

    // MARK: - Edge cases

    /// Empty service slug must degrade to a `Services` label rather
    /// than emit a malformed route or an empty H1.
    func test_pagePrompt_fallsBackOnEmptyService() {
        let prompt = SEOSwarmPromptBuilder.pagePrompt(
            project: sampleProject(),
            service: "   ",
            zone: sampleZone()
        )
        XCTAssertTrue(prompt.contains("Services"))
    }

    /// Population provided → the prompt mentions the zone population
    /// so Claude can ground the copy locally.
    func test_pagePrompt_mentionsPopulationWhenProvided() {
        let prompt = SEOSwarmPromptBuilder.pagePrompt(
            project: sampleProject(),
            service: "verriere",
            zone: sampleZone(population: 45_000)
        )
        XCTAssertTrue(prompt.contains("45000") || prompt.contains("45 000") || prompt.contains("~45"))
    }

    /// Population nil → the prompt explicitly forbids fabricating a
    /// demographic chiffre. Locks the no-hallucination guardrail.
    func test_pagePrompt_forbidsFabricationWhenPopulationNil() {
        let prompt = SEOSwarmPromptBuilder.pagePrompt(
            project: sampleProject(),
            service: "verriere",
            zone: sampleZone(population: nil)
        )
        XCTAssertTrue(prompt.contains("non fournie"))
        XCTAssertTrue(prompt.contains("NE PAS inventer"))
    }
}
