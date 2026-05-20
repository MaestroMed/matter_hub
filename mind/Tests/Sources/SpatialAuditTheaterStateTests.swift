import XCTest
@testable import VisionSpatialKit

/// v1.0-alpha.19 — Locks the pure math behind the `SpatialAuditTheater`
/// half-arc placement. Every test here runs on the iOS host simulator
/// (no visionOS runtime required) because `TheaterPlacement` itself is
/// pure value-type math — no `RealityView`, no `SwiftUI`, no `XRDevice`
/// reach.
///
/// Acceptance criteria:
///   - empty input → empty output
///   - single card sits centre
///   - N cards distribute symmetrically across the half-arc
///   - the input is clamped at `maxPlacements = 8`
///   - every placement sits within the bounding radius
///   - the synthesis panel sits straight ahead
final class SpatialAuditTheaterStateTests: XCTestCase {

    // MARK: - Empty / boundary

    func test_placements_emptyInput_returnsEmptyOutput() {
        XCTAssertTrue(TheaterPlacement.placements(count: 0).isEmpty)
        XCTAssertTrue(TheaterPlacement.placements(count: -1).isEmpty)
    }

    func test_placements_singleCard_sitsDeadCentre() {
        let placements = TheaterPlacement.placements(count: 1)
        XCTAssertEqual(placements.count, 1)
        let centre = placements[0]
        XCTAssertEqual(centre.angle, 0, accuracy: 1e-9)
        XCTAssertEqual(centre.x, 0, accuracy: 1e-9)
        XCTAssertEqual(centre.y, 0, accuracy: 1e-9)
        XCTAssertEqual(centre.z, -TheaterPlacement.arcRadiusMeters, accuracy: 1e-9)
    }

    // MARK: - Symmetric distribution

    func test_placements_twoCards_sitAtBothExtremes() {
        let placements = TheaterPlacement.placements(count: 2)
        XCTAssertEqual(placements.count, 2)
        XCTAssertEqual(placements[0].angle, -TheaterPlacement.arcHalfAngle, accuracy: 1e-9)
        XCTAssertEqual(placements[1].angle, +TheaterPlacement.arcHalfAngle, accuracy: 1e-9)
        // Mirror symmetry on the x axis.
        XCTAssertEqual(placements[0].x, -placements[1].x, accuracy: 1e-9)
        // Same depth + height — both at the extremes.
        XCTAssertEqual(placements[0].z, placements[1].z, accuracy: 1e-9)
        XCTAssertEqual(placements[0].y, placements[1].y, accuracy: 1e-9)
    }

    func test_placements_fiveCards_spreadEvenlyAcrossArc() {
        let placements = TheaterPlacement.placements(count: 5)
        XCTAssertEqual(placements.count, 5)
        // Middle card sits straight ahead.
        XCTAssertEqual(placements[2].angle, 0, accuracy: 1e-9)
        // First and last cards sit at the extremes.
        XCTAssertEqual(placements[0].angle, -TheaterPlacement.arcHalfAngle, accuracy: 1e-9)
        XCTAssertEqual(placements[4].angle, +TheaterPlacement.arcHalfAngle, accuracy: 1e-9)
        // Symmetric pair around centre.
        XCTAssertEqual(placements[1].angle, -placements[3].angle, accuracy: 1e-9)
        // Adjacent step is consistent.
        let step01 = placements[1].angle - placements[0].angle
        let step12 = placements[2].angle - placements[1].angle
        XCTAssertEqual(step01, step12, accuracy: 1e-9)
    }

    // MARK: - Clamping

    func test_placements_aboveMax_clampedToMaxPlacements() {
        let placements = TheaterPlacement.placements(count: 25)
        XCTAssertEqual(placements.count, TheaterPlacement.maxPlacements)
        XCTAssertEqual(TheaterPlacement.maxPlacements, 8)
    }

    func test_placements_eachCardWithinBoundingRadius() {
        let placements = TheaterPlacement.placements(count: 6)
        let radius = TheaterPlacement.arcRadiusMeters
        for placement in placements {
            // sqrt(x^2 + z^2) ≈ radius (the arc is circular in the
            // horizontal plane).
            let horizontalRadius = sqrt(placement.x * placement.x + placement.z * placement.z)
            XCTAssertEqual(horizontalRadius, radius, accuracy: 1e-9)
            // y stays bounded by the vertical-rise envelope.
            XCTAssertGreaterThanOrEqual(placement.y, 0)
            XCTAssertLessThanOrEqual(placement.y, TheaterPlacement.verticalRiseMeters)
        }
    }

    // MARK: - Synthesis panel

    func test_synthesisPanel_sitsStraightAhead() {
        let panel = TheaterPlacement.synthesisPanel
        XCTAssertEqual(panel.x, 0, accuracy: 1e-9)
        XCTAssertEqual(panel.y, 0, accuracy: 1e-9)
        XCTAssertEqual(panel.z, -TheaterPlacement.arcRadiusMeters, accuracy: 1e-9)
        XCTAssertEqual(panel.angle, 0, accuracy: 1e-9)
        // Distinct index from the quick-win arc (negative sentinel).
        XCTAssertEqual(panel.index, -1)
    }
}
