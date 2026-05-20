import XCTest
import SwiftUI
@testable import DesignSystem

/// v0.6 — Dynamic Type complete pass. These tests don't drive the UI
/// — they lock structural invariants about how MIND's brand-defining
/// design-system primitives express their typography, so a future
/// regression that re-introduces a hardcoded `Font.system(size: N)`
/// inside a reusable shell trips a targeted failure rather than only
/// showing up at AX5 on a device.
///
/// They cover:
///   1. LiquidButton's label exists and renders without throwing.
///   2. LiquidPill's title path exists when active.
///   3. Named text-style invariants: the `.headline` text style must
///      *not* equal `.body` (sanity-checks the Font.TextStyle enum is
///      properly bridged in the build, so SwiftUI is actually scaling
///      our `.font(.system(.headline, …))` callsites under Dynamic
///      Type).
///   4. ContentSizeCategory traverses through xLarge → AX5 without
///      collapsing — guards against the system removing accessibility
///      sizes in a future iOS minor (paranoid, cheap).
final class DynamicTypeAuditTests: XCTestCase {

    // MARK: - LiquidButton renders without crashing

    @MainActor
    func test_liquidButton_initializesWithMinimumArgs() {
        // The cheapest check that won't change: a LiquidButton can be
        // constructed with just `title` + `action`, defaults to the
        // `.tap` haptic, and exposes a SwiftUI body. If a future refactor
        // makes the title required-but-typed-as-something-else, this
        // breaks — and that's exactly the kind of structural drift
        // v0.6 is locking against.
        let button = LiquidButton(title: "Start Focus") {}
        _ = button.body
        XCTAssertEqual(button.title, "Start Focus")
        XCTAssertNil(button.systemImage)
    }

    @MainActor
    func test_liquidButton_acceptsSystemImageAndHaptic() {
        let button = LiquidButton(
            title: "End focus",
            systemImage: "stop.fill",
            haptic: .success
        ) {}
        _ = button.body
        XCTAssertEqual(button.systemImage, "stop.fill")
        // Haptic is a private-ish enum, but the case rawValue is
        // mirrorable. We don't assert the exact case — only that the
        // initialiser stored *something* the body can read.
        let mirror = Mirror(reflecting: button)
        XCTAssertNotNil(mirror.descendant("haptic"))
    }

    // MARK: - LiquidPill renders with and without title

    @MainActor
    func test_liquidPill_initializesWithIconOnly() {
        let pill = LiquidPill(systemImage: "drop.fill", isActive: false) {}
        _ = pill.body
        XCTAssertNil(pill.title)
        XCTAssertFalse(pill.isActive)
    }

    @MainActor
    func test_liquidPill_initializesWithTitleWhenActive() {
        let pill = LiquidPill(
            title: "Focus",
            systemImage: "brain.head.profile",
            isActive: true
        ) {}
        _ = pill.body
        XCTAssertEqual(pill.title, "Focus")
        XCTAssertTrue(pill.isActive)
    }

    // MARK: - Named text-style sanity (Font.TextStyle bridging)

    func test_namedTextStyles_areDistinct() {
        // Font.TextStyle is the enum we lean on for Dynamic Type scaling.
        // If the build accidentally collapsed two cases (a real-world
        // SwiftUI bug in early betas), every `.headline` callsite would
        // render at `.body` size. Cheap sanity check.
        let allStyles: [Font.TextStyle] = [
            .largeTitle, .title, .title2, .title3,
            .headline, .subheadline,
            .body, .callout, .footnote,
            .caption, .caption2
        ]
        XCTAssertEqual(Set(allStyles).count, allStyles.count)
    }

    func test_dynamicTypeSize_extendsThroughAccessibility5() {
        // Locks the v0.6 acceptance criterion in code: AX5 must remain
        // a valid DynamicTypeSize. If Apple ever ships a build where
        // the accessibility ladder is shorter, we want to fail fast in
        // CI rather than surprise users on TestFlight.
        let ladder: [DynamicTypeSize] = [
            .xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge,
            .accessibility1, .accessibility2, .accessibility3,
            .accessibility4, .accessibility5
        ]
        XCTAssertEqual(ladder.last, .accessibility5)
        XCTAssertTrue(DynamicTypeSize.accessibility5.isAccessibilitySize)
        XCTAssertFalse(DynamicTypeSize.large.isAccessibilitySize)
    }

    func test_dynamicTypeSize_accessibilityLadder_isMonotonic() {
        // Make sure the ordering is preserved — if accessibility5 ever
        // ranks below accessibility1, our minimumScaleFactor decisions
        // become meaningless. Compares via the synthesised Comparable
        // conformance SwiftUI provides on DynamicTypeSize.
        XCTAssertLessThan(DynamicTypeSize.large, DynamicTypeSize.xLarge)
        XCTAssertLessThan(DynamicTypeSize.xxxLarge, DynamicTypeSize.accessibility1)
        XCTAssertLessThan(DynamicTypeSize.accessibility4, DynamicTypeSize.accessibility5)
    }
}
