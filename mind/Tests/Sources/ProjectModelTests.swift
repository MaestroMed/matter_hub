import XCTest
import SwiftData
@testable import GraphCore

/// v1.0-alpha.2 — Locks the Cockpit Studio `Project` @Model:
/// init defaults, slug normalisation, enum accessor round-trips,
/// touchActivity timestamping, MRR aggregation across projects,
/// lifecycle stage transitions, and the idempotent demo seeder.
@MainActor
final class ProjectModelTests: XCTestCase {

    // MARK: - Init / defaults

    /// A freshly-constructed Project carries the documented defaults:
    /// `nextjs` stack, `oneshot` contract, `active` lifecycle,
    /// 0 MRR, 0 one-shot, iris primary color, lead inbox enabled.
    /// Every drift here ripples through Cockpit cards + revenue math.
    func test_init_defaultsAreDocumented() {
        let project = Project(name: "Acme", host: "www.acme.fr")
        XCTAssertEqual(project.name, "Acme")
        XCTAssertEqual(project.host, "www.acme.fr")
        XCTAssertEqual(project.stackEnum, .nextjs)
        XCTAssertEqual(project.contractTypeEnum, .oneshot)
        XCTAssertEqual(project.lifecycleStageEnum, .active)
        XCTAssertEqual(project.monthlyRecurringRevenueEUR, 0)
        XCTAssertEqual(project.oneShotRevenueEUR, 0)
        XCTAssertEqual(project.primaryColor, "#5E5BD8",
                       "Default Project tint must stay iris (#5E5BD8) " +
                       "so unsupplied cards inherit the MIND brand.")
        XCTAssertTrue(project.leadInboxEnabled,
                      "Lead inbox is the headline feature of a Project — " +
                      "default ON, explicit opt-out.")
        XCTAssertNil(project.webhookSecret)
        XCTAssertNil(project.githubRepo)
        XCTAssertNil(project.vercelProjectID)
        // startedAt == lastActivityAt at construction time — a project
        // without activity has its "last touched" equal to its birth.
        XCTAssertEqual(project.startedAt, project.lastActivityAt)
    }

    // MARK: - Slug normalisation

    /// Plain ASCII project names lowercase and dash-join cleanly.
    func test_slug_normalizesAsciiPunctuation() {
        XCTAssertEqual(Project.normalizeSlug("AZ Construction"), "az-construction")
        XCTAssertEqual(Project.normalizeSlug("IEF & Co"), "ief-co")
        XCTAssertEqual(Project.normalizeSlug("Hello, World!"), "hello-world")
    }

    /// Diacritics fold to ASCII so a French project name slugs
    /// without `é` / `à` / `ç` artifacts.
    func test_slug_foldsDiacritics() {
        XCTAssertEqual(Project.normalizeSlug("Épée d'Argent"), "epee-d-argent")
        XCTAssertEqual(Project.normalizeSlug("Crémant Sàrl"), "cremant-sarl")
    }

    /// Slugs cap at 60 chars to leave headroom for the
    /// `<slug>-<date>` Documents folder naming convention.
    func test_slug_capsAtSixtyChars() {
        let long = String(repeating: "a", count: 200)
        let slug = Project.normalizeSlug(long)
        XCTAssertLessThanOrEqual(slug.count, 60)
    }

    /// Leading + trailing dashes are trimmed so a name like
    /// `"!Acme!"` doesn't slug to `-acme-`.
    func test_slug_trimsLeadingAndTrailingDashes() {
        XCTAssertEqual(Project.normalizeSlug("!Acme!"), "acme")
        XCTAssertEqual(Project.normalizeSlug("   spaces around   "), "spaces-around")
    }

    /// Caller-supplied slug overrides the name-derived default —
    /// the existing Numelite seed uses explicit slugs that don't
    /// always match the auto-derived ones (e.g. "ief-and-co").
    func test_init_explicitSlug_overridesNameDerived() {
        let project = Project(name: "IEF & Co", host: "iefandco.com", slug: "ief-and-co")
        XCTAssertEqual(project.slug, "ief-and-co",
                       "Explicit slug must win over name-derived default.")
    }

    // MARK: - Enum accessors round-trip

    /// `stackEnum` writes through to the raw String and reads back
    /// identically. Unknown raw values fall back to `.other`.
    func test_stackEnum_roundTripsThroughRawString() {
        let project = Project(name: "Acme", host: "acme.fr")
        for stack in ProjectStack.allCases {
            project.stackEnum = stack
            XCTAssertEqual(project.stack, stack.rawValue)
            XCTAssertEqual(project.stackEnum, stack)
        }
        // Unknown raw value falls back to `.other`.
        project.stack = "neverHeardOfIt"
        XCTAssertEqual(project.stackEnum, .other,
                       "Unknown raw values must fall back to `.other` " +
                       "so a future custom stack doesn't crash the UI.")
    }

    /// `contractTypeEnum` round-trips identically; unknown values
    /// fall back to `.oneshot` (safer for revenue math than
    /// defaulting to `.retainer`, which would multiply MRR by 12).
    func test_contractTypeEnum_roundTrips_unknownFallsBackToOneshot() {
        let project = Project(name: "Acme", host: "acme.fr")
        project.contractTypeEnum = .retainer
        XCTAssertEqual(project.contractType, "retainer")
        XCTAssertEqual(project.contractTypeEnum, .retainer)
        project.contractType = "bogus"
        XCTAssertEqual(project.contractTypeEnum, .oneshot)
    }

    /// `lifecycleStageEnum` round-trips identically; unknown values
    /// fall back to `.active` to avoid silently archiving live work.
    func test_lifecycleStageEnum_roundTrips_unknownFallsBackToActive() {
        let project = Project(name: "Acme", host: "acme.fr")
        for stage in ProjectLifecycleStage.allCases {
            project.lifecycleStageEnum = stage
            XCTAssertEqual(project.lifecycleStageEnum, stage)
        }
        project.lifecycleStage = "garbage"
        XCTAssertEqual(project.lifecycleStageEnum, .active)
    }

    // MARK: - touchActivity

    /// `touchActivity()` rewrites `lastActivityAt` to now. Verified
    /// by capturing the timestamp before and after — must be
    /// strictly greater than the construction-time value.
    func test_touchActivity_updatesLastActivityAt() async throws {
        let project = Project(name: "Acme", host: "acme.fr", startedAt: .distantPast)
        XCTAssertEqual(project.lastActivityAt, .distantPast)
        // Sleep a tick so the timestamp ratchets even on a fast Mac.
        try await Task.sleep(nanoseconds: 5_000_000)
        project.touchActivity()
        XCTAssertGreaterThan(project.lastActivityAt, .distantPast)
    }

    // MARK: - MRR aggregation

    /// Sum of MRR across a mixed-contract portfolio. Pure math
    /// helper — locks the Cockpit's expected "annualised forecast"
    /// formula.
    func test_mrrSum_aggregatesAcrossProjects() {
        let portfolio = [
            Project(name: "A", host: "a.fr", contractType: .retainer, monthlyRecurringRevenueEUR: 290),
            Project(name: "B", host: "b.fr", contractType: .retainer, monthlyRecurringRevenueEUR: 350),
            Project(name: "C", host: "c.fr", contractType: .oneshot, oneShotRevenueEUR: 5200),
        ]
        let totalMRR = portfolio
            .filter { $0.contractTypeEnum == .retainer }
            .reduce(0) { $0 + $1.monthlyRecurringRevenueEUR }
        XCTAssertEqual(totalMRR, 640,
                       "Two retainers at 290+350 should sum to 640 € MRR. " +
                       "One-shot revenue is excluded from MRR aggregation.")
    }

    // MARK: - Demo seeding

    /// `seedDemoProjects` inserts the documented 5 Numelite rows
    /// when the context is empty.
    func test_seedDemoProjects_emptyContext_insertsFiveProjects() throws {
        let container = try ModelContainer(
            for: Project.self, Lead.self, Deliverable.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let inserted = Project.seedDemoProjects(in: context)
        XCTAssertEqual(inserted, 5)
        let projects = try context.fetch(FetchDescriptor<Project>())
        XCTAssertEqual(projects.count, 5)
        let names = Set(projects.map(\.name))
        XCTAssertEqual(names, [
            "AZ Construction",
            "AZ Epoxy",
            "AZ Concept",
            "IEF & Co",
            "Sconnect",
        ])
    }

    /// `seedDemoProjects` is idempotent: a second call on a
    /// pre-seeded context inserts zero rows and leaves the existing
    /// ones untouched. Critical so a stray re-seed (lost flag, OS
    /// bug) never duplicates the portfolio.
    func test_seedDemoProjects_existingContext_isIdempotent() throws {
        let container = try ModelContainer(
            for: Project.self, Lead.self, Deliverable.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let first = Project.seedDemoProjects(in: context)
        let second = Project.seedDemoProjects(in: context)
        XCTAssertEqual(first, 5)
        XCTAssertEqual(second, 0,
                       "Second seed pass must insert zero rows to " +
                       "preserve idempotency across launches.")
        let projects = try context.fetch(FetchDescriptor<Project>())
        XCTAssertEqual(projects.count, 5)
    }
}
