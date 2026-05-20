import XCTest
@testable import HealthInsights

/// Locks the pure value-type surface WeeklySummary exposes to the rest
/// of MIND. We intentionally don't touch HKHealthStore here — that path
/// is gated by the user's HealthKit permission, and bringing up a real
/// store inside a test runner is flaky on CI (and impossible in the
/// Simulator on Mac without first seeding samples manually). The
/// actor-level `weeklySummary()` is exercised end-to-end on the
/// simulator via the HomeView "Cette semaine" card screenshot in vision
/// verification — when permission is denied the card hides itself,
/// which is the only deterministic contract worth asserting at the
/// unit-test layer.
final class HealthReaderTests: XCTestCase {

    // MARK: - Init / accessor contract

    func test_init_preservesAllFields() {
        let summary = WeeklySummary(
            totalSteps: 54_321,
            avgSleepHours: 7.5,
            activeMinutes: 240
        )
        XCTAssertEqual(summary.totalSteps, 54_321)
        XCTAssertEqual(summary.avgSleepHours, 7.5, accuracy: 0.0001)
        XCTAssertEqual(summary.activeMinutes, 240)
    }

    // MARK: - Empty canonical value

    func test_empty_isZeroOnEveryField() {
        let empty = WeeklySummary.empty
        XCTAssertEqual(empty.totalSteps, 0)
        XCTAssertEqual(empty.avgSleepHours, 0, accuracy: 0.0001)
        XCTAssertEqual(empty.activeMinutes, 0)
    }

    func test_empty_isReusedSoCardSoftFailsConsistently() {
        // The reader's documented soft-fail contract is to return the
        // canonical `.empty` value — not a freshly-built zero. Equality
        // (Equatable conformance) is the API HomeView uses to decide
        // whether to render the card, so we lock it here.
        let other = WeeklySummary(totalSteps: 0, avgSleepHours: 0, activeMinutes: 0)
        XCTAssertEqual(other, WeeklySummary.empty,
                       "Any zero-valued summary must compare equal to .empty so HomeView can use a single render gate")
    }

    // MARK: - Meaningfulness

    func test_isMeaningful_returnsFalseForEmpty() {
        XCTAssertFalse(WeeklySummary.empty.isMeaningful,
                       "An all-zero summary must hide the home card — never render '0 steps · 0h · 0 min' to a fresh user")
    }

    func test_isMeaningful_returnsTrueWhenAnyFieldIsNonZero() {
        XCTAssertTrue(WeeklySummary(totalSteps: 1, avgSleepHours: 0, activeMinutes: 0).isMeaningful)
        XCTAssertTrue(WeeklySummary(totalSteps: 0, avgSleepHours: 0.1, activeMinutes: 0).isMeaningful)
        XCTAssertTrue(WeeklySummary(totalSteps: 0, avgSleepHours: 0, activeMinutes: 1).isMeaningful)
        XCTAssertTrue(WeeklySummary(totalSteps: 12_345, avgSleepHours: 7.5, activeMinutes: 210).isMeaningful)
    }

    // MARK: - Equatable contract

    func test_equality_isFieldwise() {
        let a = WeeklySummary(totalSteps: 100, avgSleepHours: 7, activeMinutes: 20)
        let b = WeeklySummary(totalSteps: 100, avgSleepHours: 7, activeMinutes: 20)
        let c = WeeklySummary(totalSteps: 101, avgSleepHours: 7, activeMinutes: 20)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c,
                          "A one-step difference must compare unequal so SwiftUI re-renders the home card without an explicit id() bump")
    }
}
