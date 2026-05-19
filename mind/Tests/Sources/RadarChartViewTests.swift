import XCTest
import SwiftUI
@testable import DesignSystem

/// v0.24 — Covers the pure geometry helpers behind `RadarChartView`:
/// the clamping rule, the empty-axes guard, and the polygon
/// projection formula. The Canvas render itself is exercised by
/// the simulator screenshot — these tests pin the math so a
/// future tweak to the angle convention can't silently rotate the
/// chart.
final class RadarChartViewTests: XCTestCase {

    private let center = CGPoint(x: 100, y: 100)
    private let radius: CGFloat = 80

    /// Values get clamped into [0, 100] before projection so a
    /// noisy upstream (e.g. a malformed PageSpeed payload) can't
    /// shoot the polygon outside the radar.
    func test_clamp_keepsValuesIn0To100() {
        XCTAssertEqual(RadarChartView.clamp(-10), 0)
        XCTAssertEqual(RadarChartView.clamp(0), 0)
        XCTAssertEqual(RadarChartView.clamp(50), 50)
        XCTAssertEqual(RadarChartView.clamp(100), 100)
        XCTAssertEqual(RadarChartView.clamp(250), 100)
    }

    /// Series shorter than the axis count: the missing values are
    /// treated as zero so the polygon still closes around the
    /// origin. Catches the case where a participant's audit
    /// partially failed and only some scores landed.
    func test_polygonPoints_padShortSeriesWithZeros() {
        let axes = ["A", "B", "C", "D"]
        let pts = RadarChartView.polygonPoints(
            values: [100, 100],
            axes: axes,
            center: center,
            radius: radius
        )
        XCTAssertEqual(pts.count, 4)
        // First two reach the full radius (axes at -90° and 0°).
        XCTAssertEqual(pts[0].x, 100, accuracy: 0.001)
        XCTAssertEqual(pts[0].y, 20, accuracy: 0.001)
        XCTAssertEqual(pts[1].x, 180, accuracy: 0.001)
        XCTAssertEqual(pts[1].y, 100, accuracy: 0.001)
        // Last two collapsed to the centre because the values are
        // implicitly zero. Polygon still closes cleanly.
        XCTAssertEqual(pts[2], center)
        XCTAssertEqual(pts[3], center)
    }

    /// Empty axes returns an empty point array so the Canvas
    /// renders a silent empty chart while a battle is still
    /// resolving (no crash, no log spam).
    func test_polygonPoints_emptyAxesReturnsEmpty() {
        let pts = RadarChartView.polygonPoints(
            values: [50, 50, 50],
            axes: [],
            center: center,
            radius: radius
        )
        XCTAssertTrue(pts.isEmpty)
    }

    /// Polygon formula sanity: a full-score (100) value on a single
    /// axis projects to the radar edge at the expected angle. Axis
    /// 0 of 4 axes sits at -π/2 (12 o'clock), so the point is
    /// directly above the centre.
    func test_polygonPoints_fullScoreProjectsToEdge() {
        let axes = ["A", "B", "C", "D"]
        let pts = RadarChartView.polygonPoints(
            values: [100, 0, 0, 0],
            axes: axes,
            center: center,
            radius: radius
        )
        XCTAssertEqual(pts.count, 4)
        // (centerX + 80*cos(-π/2), centerY + 80*sin(-π/2)) = (100, 20)
        XCTAssertEqual(pts[0].x, 100, accuracy: 0.001)
        XCTAssertEqual(pts[0].y, 20, accuracy: 0.001)
        // Axis 2 of 4 sits at +π/2 — directly below the centre.
        // Value 0 → collapsed to centre.
        XCTAssertEqual(pts[2], center)
    }
}
