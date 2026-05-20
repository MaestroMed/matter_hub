import XCTest
@testable import OutreachKit
@testable import GraphCore

/// v1.0-alpha.13 — Locks the pure parts of the AI Reply Composer.
/// The `OutreachEmailGenerator.leadReply` network call itself can't
/// be exercised from a hosted unit test (no Anthropic key in CI),
/// so the contract covered here is everything observable from the
/// builder + parser.
final class LeadReplyPromptBuilderTests: XCTestCase {

    // MARK: - Fixtures

    @MainActor
    private func sampleLead(
        contactName: String = "Sarah Bensalem",
        contactEmail: String = "sarah@iefandco.com",
        message: String = "Bonjour, nous souhaitons refondre notre site vitrine."
    ) -> Lead {
        Lead(
            contactName: contactName,
            contactEmail: contactEmail,
            message: message
        )
    }

    @MainActor
    private func sampleProject(
        name: String = "IEF & Co",
        host: String = "www.iefandco.com",
        contractType: ProjectContractType = .retainer
    ) -> Project {
        Project(
            name: name,
            host: host,
            contractType: contractType
        )
    }

    // MARK: - Pure prompt anchors

    @MainActor
    func test_build_systemPromptMentionsFrench() {
        let lead = sampleLead()
        let prompt = LeadReplyPromptBuilder.build(
            lead: lead,
            project: nil,
            similarProjects: []
        )
        XCTAssertTrue(
            prompt.contains("French") || prompt.contains("français"),
            "Prompt must instruct Claude to produce French replies"
        )
    }

    @MainActor
    func test_build_directAnglePromptAsksForConciseAndSlot() {
        let lead = sampleLead()
        let prompt = LeadReplyPromptBuilder.build(
            lead: lead,
            project: nil,
            similarProjects: []
        )
        XCTAssertTrue(
            prompt.contains("\"direct\""),
            "Direct angle case label must be locked in the prompt"
        )
        XCTAssertTrue(
            prompt.contains("concrete call slot") || prompt.contains("propose"),
            "Direct angle must request a call slot proposal: \(prompt)"
        )
    }

    @MainActor
    func test_build_consultativeAngleAsks2QualifyingQuestions() {
        let lead = sampleLead()
        let prompt = LeadReplyPromptBuilder.build(
            lead: lead,
            project: nil,
            similarProjects: []
        )
        XCTAssertTrue(
            prompt.contains("\"consultative\""),
            "Consultative angle label must be locked"
        )
        XCTAssertTrue(
            prompt.contains("2 qualifying questions") || prompt.contains("exactly 2"),
            "Consultative angle must ask for exactly 2 qualifying questions"
        )
    }

    @MainActor
    func test_build_similarCaseRequiresSimilarProjectsOrFallsBack() {
        // With similarProjects empty — must instruct fallback to a
        // generic peer reference, not invent a fake name.
        let lead = sampleLead()
        let withoutSimilar = LeadReplyPromptBuilder.build(
            lead: lead,
            project: nil,
            similarProjects: []
        )
        XCTAssertTrue(
            withoutSimilar.contains("Similar past engagements: NONE"),
            "Without similarProjects, prompt must explicitly note the absence"
        )

        // With similarProjects populated — must enumerate them.
        let project = sampleProject(name: "AZ Construction", host: "www.azconstruction.fr")
        let withSimilar = LeadReplyPromptBuilder.build(
            lead: lead,
            project: nil,
            similarProjects: [project]
        )
        XCTAssertTrue(
            withSimilar.contains("AZ Construction"),
            "Provided similar project must appear in the prompt body"
        )
    }

    @MainActor
    func test_build_includesLeadMessageVerbatim() {
        let lead = sampleLead(message: "Pouvez-vous me chiffrer une refonte e-commerce ?")
        let prompt = LeadReplyPromptBuilder.build(
            lead: lead,
            project: nil,
            similarProjects: []
        )
        XCTAssertTrue(
            prompt.contains("Pouvez-vous me chiffrer une refonte e-commerce ?"),
            "Lead message body must appear verbatim in the prompt grounding"
        )
    }

    @MainActor
    func test_build_includesProjectNameWhenPresent() {
        let lead = sampleLead()
        let project = sampleProject()
        let prompt = LeadReplyPromptBuilder.build(
            lead: lead,
            project: project,
            similarProjects: []
        )
        XCTAssertTrue(
            prompt.contains("IEF & Co"),
            "Project name must appear in the prompt's project context line"
        )
    }

    @MainActor
    func test_build_handlesEmptyLeadMessageGracefully() {
        let lead = sampleLead(message: "")
        let prompt = LeadReplyPromptBuilder.build(
            lead: lead,
            project: nil,
            similarProjects: []
        )
        XCTAssertTrue(
            prompt.contains("EMPTY") ||
            prompt.contains("acknowledgement"),
            "Empty lead message must still yield a valid prompt with an explicit empty handler"
        )
    }

    @MainActor
    func test_build_isDeterministicForSameInput() {
        let lead = sampleLead()
        let project = sampleProject()
        let a = LeadReplyPromptBuilder.build(
            lead: lead,
            project: project,
            similarProjects: []
        )
        let b = LeadReplyPromptBuilder.build(
            lead: lead,
            project: project,
            similarProjects: []
        )
        XCTAssertEqual(
            a, b,
            "Builder must be pure — identical inputs → identical prompt strings"
        )
    }

    @MainActor
    func test_build_asksFor3VariantsAsJsonArray() {
        let lead = sampleLead()
        let prompt = LeadReplyPromptBuilder.build(
            lead: lead,
            project: nil,
            similarProjects: []
        )
        XCTAssertTrue(
            prompt.contains("3 distinct"),
            "Prompt must ask for exactly 3 variants"
        )
        XCTAssertTrue(
            prompt.contains("STRICTLY with valid JSON"),
            "Prompt must instruct Claude to emit raw JSON only"
        )
        XCTAssertTrue(
            prompt.contains("\"variants\""),
            "JSON schema must wrap the array in a 'variants' key"
        )
        XCTAssertTrue(
            prompt.contains("\"angle\""),
            "JSON schema must include the 'angle' field"
        )
        XCTAssertTrue(
            prompt.contains("\"body\""),
            "JSON schema must include the 'body' field"
        )
    }

    @MainActor
    func test_build_mentionsMehdiAsSender() {
        let lead = sampleLead()
        let prompt = LeadReplyPromptBuilder.build(
            lead: lead,
            project: nil,
            similarProjects: []
        )
        XCTAssertTrue(
            prompt.contains("Mehdi"),
            "Prompt must identify Mehdi as the sender"
        )
        XCTAssertTrue(
            prompt.contains("Numelite") ||
            prompt.contains("Senior Digital Consultant"),
            "Prompt must convey Mehdi's role / agency context"
        )
    }

    // MARK: - Parser round-trip

    func test_parse_roundTripsWellFormedPayload() {
        let response = """
        {
          "variants": [
            { "angle": "direct", "body": "Bonjour Sarah,\\n\\nRéponse directe.\\n\\n— Mehdi" },
            { "angle": "consultative", "body": "Bonjour Sarah,\\n\\n2 questions.\\n\\n— Mehdi" },
            { "angle": "similarCase", "body": "Bonjour Sarah,\\n\\nClient similaire.\\n\\n— Mehdi" }
          ]
        }
        """
        let variants = LeadReplyPromptBuilder.parse(response: response)
        XCTAssertEqual(variants.count, 3)
        XCTAssertEqual(variants[0].angle, .direct)
        XCTAssertEqual(variants[1].angle, .consultative)
        XCTAssertEqual(variants[2].angle, .similarCase)
    }

    func test_parse_softFailsOnInvalidJSON() {
        let response = "not actually json"
        let variants = LeadReplyPromptBuilder.parse(response: response)
        XCTAssertTrue(
            variants.isEmpty,
            "Invalid JSON must soft-fail to an empty array, never throw"
        )
    }
}
