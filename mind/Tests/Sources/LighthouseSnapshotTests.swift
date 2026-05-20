import XCTest
@testable import GraphCore

/// v1.1.0 — Locks the `LighthouseSnapshot` value contract — default
/// field initializers, score clamping, metric accessor projection.
/// SwiftData persistence is not exercised here (tests stay pure);
/// the persistence path is covered by the host-side smoke test in
/// `LighthouseSnapshotStore.persist(...)`.
final class LighthouseSnapshotTests: XCTestCase {

    func test_init_storesEveryFieldVerbatim() {
        let projectID = UUID()
        let captured = Date(timeIntervalSince1970: 1_716_000_000)
        let snapshot = LighthouseSnapshot(
            id: UUID(),
            capturedAt: captured,
            projectID: projectID,
            host: "www.az-construction.fr",
            strategy: "desktop",
            performance: 92,
            accessibility: 88,
            bestPractices: 95,
            seo: 91,
            lcpSeconds: 2.1,
            inpMs: 180,
            cls: 0.05
        )
        XCTAssertEqual(snapshot.capturedAt, captured)
        XCTAssertEqual(snapshot.projectID, projectID)
        XCTAssertEqual(snapshot.host, "www.az-construction.fr")
        XCTAssertEqual(snapshot.strategy, "desktop")
        XCTAssertEqual(snapshot.performance, 92)
        XCTAssertEqual(snapshot.accessibility, 88)
        XCTAssertEqual(snapshot.bestPractices, 95)
        XCTAssertEqual(snapshot.seo, 91)
        XCTAssertEqual(snapshot.lcpSeconds, 2.1, accuracy: 0.0001)
        XCTAssertEqual(snapshot.inpMs, 180)
        XCTAssertEqual(snapshot.cls, 0.05, accuracy: 0.0001)
    }

    func test_clampScore_capsAtZeroAndOneHundred() {
        XCTAssertEqual(LighthouseSnapshot.clampScore(-12), 0)
        XCTAssertEqual(LighthouseSnapshot.clampScore(0), 0)
        XCTAssertEqual(LighthouseSnapshot.clampScore(50), 50)
        XCTAssertEqual(LighthouseSnapshot.clampScore(100), 100)
        XCTAssertEqual(LighthouseSnapshot.clampScore(101), 100)
        XCTAssertEqual(LighthouseSnapshot.clampScore(420), 100)
    }

    func test_init_clampsOutOfRangeCategoryScores() {
        let snapshot = LighthouseSnapshot(
            projectID: UUID(),
            performance: 110,
            accessibility: -5,
            bestPractices: 200,
            seo: 90
        )
        XCTAssertEqual(snapshot.performance, 100)
        XCTAssertEqual(snapshot.accessibility, 0)
        XCTAssertEqual(snapshot.bestPractices, 100)
        XCTAssertEqual(snapshot.seo, 90)
    }

    func test_init_clampsNegativeWebVitals() {
        let snapshot = LighthouseSnapshot(
            projectID: UUID(),
            lcpSeconds: -1.5,
            inpMs: -50,
            cls: -0.1
        )
        XCTAssertEqual(snapshot.lcpSeconds, 0)
        XCTAssertEqual(snapshot.inpMs, 0)
        XCTAssertEqual(snapshot.cls, 0)
    }

    func test_defaultStrategyIsMobile() {
        let snapshot = LighthouseSnapshot(projectID: UUID())
        XCTAssertEqual(snapshot.strategy, "mobile")
    }

    func test_lighthouseMetric_localizationKeysMatchCockpitVocabulary() {
        XCTAssertEqual(LighthouseMetric.performance.localizationKey, "project.lighthouse.trend.metric.perf")
        XCTAssertEqual(LighthouseMetric.accessibility.localizationKey, "project.lighthouse.trend.metric.a11y")
        XCTAssertEqual(LighthouseMetric.bestPractices.localizationKey, "project.lighthouse.trend.metric.bp")
        XCTAssertEqual(LighthouseMetric.seo.localizationKey, "project.lighthouse.trend.metric.seo")
    }

    func test_lighthouseMetric_valueInSnapshot_returnsRightField() {
        let snapshot = LighthouseSnapshot(
            projectID: UUID(),
            performance: 81,
            accessibility: 92,
            bestPractices: 73,
            seo: 64
        )
        XCTAssertEqual(LighthouseMetric.performance.value(in: snapshot), 81)
        XCTAssertEqual(LighthouseMetric.accessibility.value(in: snapshot), 92)
        XCTAssertEqual(LighthouseMetric.bestPractices.value(in: snapshot), 73)
        XCTAssertEqual(LighthouseMetric.seo.value(in: snapshot), 64)
    }

    func test_lighthouseMetric_allCases_listsEveryMetric() {
        let all = LighthouseMetric.allCases
        XCTAssertEqual(all.count, 4)
        XCTAssertTrue(all.contains(.performance))
        XCTAssertTrue(all.contains(.accessibility))
        XCTAssertTrue(all.contains(.bestPractices))
        XCTAssertTrue(all.contains(.seo))
    }
}
