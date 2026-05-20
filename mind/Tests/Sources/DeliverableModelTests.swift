import XCTest
import SwiftData
@testable import GraphCore

/// v1.0-alpha.2 — Locks the Cockpit Studio `Deliverable` @Model:
/// init defaults, kind enum round-trip with `.asset` fallback,
/// project relationship, optional fields persist.
@MainActor
final class DeliverableModelTests: XCTestCase {

    /// A bare Deliverable carries the `.page` default kind, empty
    /// title + detail, zero size, no commit metadata. Locks the
    /// shape every Cockpit row falls back to when an empty
    /// deliverable is being constructed in-flight.
    func test_init_defaultsAreDocumented() {
        let deliverable = Deliverable()
        XCTAssertEqual(deliverable.kindEnum, .page,
                       "Default kind is `.page` — the most common " +
                       "deliverable on a Numelite SEO engagement.")
        XCTAssertEqual(deliverable.title, "")
        XCTAssertEqual(deliverable.detail, "")
        XCTAssertEqual(deliverable.sizeBytes, 0)
        XCTAssertNil(deliverable.url)
        XCTAssertNil(deliverable.thumbnailPath)
        XCTAssertNil(deliverable.commitSHA)
        XCTAssertNil(deliverable.commitMessage)
        XCTAssertNil(deliverable.project)
    }

    /// All explicit init arguments survive verbatim.
    func test_init_allArgumentsPersist() {
        let now = Date()
        let deliverable = Deliverable(
            createdAt: now,
            kind: .audit,
            title: "Audit 2026-05",
            detail: "Lighthouse + sécurité",
            url: "https://www.azconstruction.fr/audit/2026-05.pdf",
            thumbnailPath: "thumbnails/audit-2026-05.png",
            sizeBytes: 245_000,
            commitSHA: "deadbeefcafebabe",
            commitMessage: "Audit Q2 finalised"
        )
        XCTAssertEqual(deliverable.createdAt, now)
        XCTAssertEqual(deliverable.kindEnum, .audit)
        XCTAssertEqual(deliverable.title, "Audit 2026-05")
        XCTAssertEqual(deliverable.detail, "Lighthouse + sécurité")
        XCTAssertEqual(deliverable.url, "https://www.azconstruction.fr/audit/2026-05.pdf")
        XCTAssertEqual(deliverable.thumbnailPath, "thumbnails/audit-2026-05.png")
        XCTAssertEqual(deliverable.sizeBytes, 245_000)
        XCTAssertEqual(deliverable.commitSHA, "deadbeefcafebabe")
        XCTAssertEqual(deliverable.commitMessage, "Audit Q2 finalised")
    }

    /// Every DeliverableKind round-trips identically through the
    /// raw String storage.
    func test_kindEnum_everyCase_roundTrips() {
        let deliverable = Deliverable()
        for kind in DeliverableKind.allCases {
            deliverable.kindEnum = kind
            XCTAssertEqual(deliverable.kind, kind.rawValue)
            XCTAssertEqual(deliverable.kindEnum, kind)
        }
    }

    /// Unknown raw kind values fall back to `.asset` because a
    /// generic asset is the safest catch-all — `.page` would
    /// imply a URL exists, `.invoice` would imply VAT math.
    func test_kindEnum_unknownRaw_fallsBackToAsset() {
        let deliverable = Deliverable()
        deliverable.kind = "proposal"
        XCTAssertEqual(deliverable.kindEnum, .asset,
                       "Unknown kind raw values must surface as `.asset` " +
                       "rather than misrepresenting as `.page` / `.invoice`.")
    }

    /// Attaching a Deliverable to a Project via the `project`
    /// relationship survives an in-memory SwiftData round-trip.
    /// Locks the Cockpit's "show every deliverable for AZ
    /// Construction" query, which walks `project.deliverables`.
    func test_projectRelationship_inMemoryRoundTrip() throws {
        let container = try ModelContainer(
            for: Project.self, Lead.self, Deliverable.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let project = Project(name: "AZ Construction", host: "www.azconstruction.fr")
        let deliverable = Deliverable(
            kind: .page,
            title: "/services/peinture",
            url: "https://www.azconstruction.fr/services/peinture",
            project: project
        )
        context.insert(project)
        context.insert(deliverable)
        try context.save()
        // Refetch the project and verify the inverse relationship
        // surfaces the deliverable. Walks the same query path the
        // Cockpit feed uses.
        let projects = try context.fetch(FetchDescriptor<Project>())
        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects[0].deliverables?.count, 1)
        XCTAssertEqual(projects[0].deliverables?.first?.title, "/services/peinture")
    }

    /// A Deliverable with no commit metadata stays nil on both
    /// `commitSHA` and `commitMessage` — `.invoice` / `.audit`
    /// kinds typically skip the git surface.
    func test_deliverable_invoiceKind_hasNoCommitMetadata() {
        let deliverable = Deliverable(kind: .invoice, title: "MIND-2026-0001")
        XCTAssertNil(deliverable.commitSHA)
        XCTAssertNil(deliverable.commitMessage)
        XCTAssertEqual(deliverable.kindEnum, .invoice)
    }
}
