import XCTest
@testable import GraphCore

/// v1.0-alpha.3 — Locks `ProjectSorter.sort(_:by:)` + the search
/// filter. Eight tests cover the three sort keys, archived bottom-
/// pin, alphabetical FR locale, empty input, single-row preservation,
/// and the filter helper.
@MainActor
final class ProjectSortingTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func project(
        name: String,
        mrr: Int = 0,
        contract: ProjectContractType = .retainer,
        stage: ProjectLifecycleStage = .active,
        activity: TimeInterval = 0,
        host: String? = nil
    ) -> Project {
        let project = Project(
            name: name,
            host: host ?? "\(name.lowercased()).fr",
            contractType: contract,
            monthlyRecurringRevenueEUR: mrr,
            lifecycleStage: stage,
            startedAt: now.addingTimeInterval(activity)
        )
        project.lastActivityAt = now.addingTimeInterval(activity)
        return project
    }

    // MARK: - activityDescending

    /// Default key: most-recently-touched projects float to the top.
    func test_activityDescending_sortsMostRecentlyTouchedFirst() {
        let input = [
            project(name: "A", activity: -300),
            project(name: "B", activity: 0),
            project(name: "C", activity: -100),
        ]
        let sorted = ProjectSorter.sort(input, by: .activityDescending)
        XCTAssertEqual(sorted.map(\.name), ["B", "C", "A"])
    }

    // MARK: - mrrDescending

    /// Biggest MRR retainers float to the top. Oneshot rows with 0
    /// MRR fall to the bottom of the active pool.
    func test_mrrDescending_sortsLargestRetainerFirst() {
        let input = [
            project(name: "Small", mrr: 100),
            project(name: "Oneshot", mrr: 0, contract: .oneshot),
            project(name: "Big", mrr: 500),
            project(name: "Mid", mrr: 250),
        ]
        let sorted = ProjectSorter.sort(input, by: .mrrDescending)
        XCTAssertEqual(sorted.map(\.name), ["Big", "Mid", "Small", "Oneshot"])
    }

    // MARK: - alphabetical (locale-aware FR)

    /// Alphabetical sort folds diacritics so "Épée" sits where "Epee"
    /// would — Mehdi's FR portfolio reads naturally rather than with
    /// all the accents grouped at the end of the list.
    func test_alphabetical_isLocaleAwareForFrench() {
        let input = [
            project(name: "Zenith"),
            project(name: "Épée d'Argent"),
            project(name: "Acme"),
            project(name: "Édition Limitée"),
        ]
        let sorted = ProjectSorter.sort(input, by: .alphabetical)
        // Acme, Édition, Épée, Zenith — the two É-prefixed names sit
        // between Acme and Zenith, not at the end.
        XCTAssertEqual(sorted.map(\.name), ["Acme", "Édition Limitée", "Épée d'Argent", "Zenith"])
    }

    // MARK: - archived sink to the bottom

    /// Archived projects always group at the bottom regardless of
    /// sort key — verifies the documented Cockpit "active first"
    /// convention.
    func test_archivedProjects_sinkToBottom_evenWithHigherMRR() {
        let input = [
            project(name: "Archived big", mrr: 999, stage: .archived),
            project(name: "Active small", mrr: 100, stage: .active),
            project(name: "Maint", mrr: 200, stage: .maintenance),
        ]
        let sorted = ProjectSorter.sort(input, by: .mrrDescending)
        XCTAssertEqual(sorted.map(\.name), ["Maint", "Active small", "Archived big"])
    }

    /// Inside the archived bucket the chosen key still applies — two
    /// archived rows still sort relative to each other.
    func test_multipleArchived_sortInternallyByKey() {
        let input = [
            project(name: "Old archived",    mrr: 100, stage: .archived, activity: -300),
            project(name: "Newer archived",  mrr: 200, stage: .archived, activity: 0),
            project(name: "Active",          mrr: 50,  stage: .active),
        ]
        let sorted = ProjectSorter.sort(input, by: .activityDescending)
        XCTAssertEqual(sorted.map(\.name), ["Active", "Newer archived", "Old archived"])
    }

    // MARK: - short-circuits

    /// Empty input returns empty output (short-circuit, no allocator
    /// thrash on the zero-row path).
    func test_emptyInput_returnsEmpty() {
        let sorted = ProjectSorter.sort([], by: .activityDescending)
        XCTAssertEqual(sorted.count, 0)
    }

    /// Single-row input round-trips unchanged.
    func test_singleProject_isPreserved() {
        let solo = project(name: "Solo")
        let sorted = ProjectSorter.sort([solo], by: .mrrDescending)
        XCTAssertEqual(sorted.count, 1)
        XCTAssertEqual(sorted.first?.name, "Solo")
    }

    // MARK: - filter helper

    /// `filter(_:query:)` matches case-insensitive substrings against
    /// the project name and host. Empty needle returns the unfiltered
    /// input.
    func test_filter_matchesNameAndHostCaseInsensitively() {
        let input = [
            project(name: "AZ Construction", host: "www.azconstruction.fr"),
            project(name: "IEF & Co",        host: "www.iefandco.com"),
            project(name: "Sconnect",        host: "sconnect.fr"),
        ]
        XCTAssertEqual(
            ProjectSorter.filter(input, query: "az").map(\.name),
            ["AZ Construction"]
        )
        XCTAssertEqual(
            ProjectSorter.filter(input, query: "IEFANDCO").map(\.name),
            ["IEF & Co"]
        )
        XCTAssertEqual(ProjectSorter.filter(input, query: "  ").count, input.count,
                       "Whitespace-only query must return the unfiltered input.")
    }
}
