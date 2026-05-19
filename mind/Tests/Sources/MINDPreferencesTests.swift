import XCTest
@testable import Settings

/// Locks the public contract of MINDPreferences — defaults, clamp,
/// persistence, and the static `currentXxx` accessors that
/// non-Observable callers (AuditNotifier, FocusController) rely on.
///
/// Tests use a throwaway UserDefaults suite per case so they never
/// touch the real `group.app.mind.ios` app-group store. The suite is
/// removed in tearDown so back-to-back runs start clean.
@MainActor
final class MINDPreferencesTests: XCTestCase {

    private var suiteName: String!

    override func setUp() {
        super.setUp()
        // Unique suite per test so parallel runs (Xcode 16 default) and
        // back-to-back invocations never bleed state into each other.
        suiteName = "mind.test.\(UUID().uuidString)"
    }

    override func tearDown() {
        if let suiteName {
            UserDefaults().removePersistentDomain(forName: suiteName)
        }
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Defaults

    func test_focusDurationMinutes_defaultsTo25_pomodoro() {
        let prefs = MINDPreferences(suiteName: suiteName)
        XCTAssertEqual(prefs.focusDurationMinutes, 25)
    }

    func test_auditNotificationsEnabled_defaultsToTrue() {
        let prefs = MINDPreferences(suiteName: suiteName)
        XCTAssertTrue(prefs.auditNotificationsEnabled,
                      "First-run users get notifs on so they discover the feature")
    }

    func test_sentryDSN_defaultsToEmptyString() {
        let prefs = MINDPreferences(suiteName: suiteName)
        XCTAssertEqual(prefs.sentryDSN, "",
                       "Telemetry is opt-in — empty default means Sentry stays off")
    }

    // MARK: - Clamp on focus duration

    func test_focusDurationMinutes_clampedToMinimum5() {
        let prefs = MINDPreferences(suiteName: suiteName)
        prefs.focusDurationMinutes = 2          // below floor
        XCTAssertEqual(prefs.focusDurationMinutes, 5)
    }

    func test_focusDurationMinutes_clampedToMaximum180() {
        let prefs = MINDPreferences(suiteName: suiteName)
        prefs.focusDurationMinutes = 600        // above ceiling
        XCTAssertEqual(prefs.focusDurationMinutes, 180)
    }

    func test_focusDurationMinutes_acceptsInRangeValues() {
        let prefs = MINDPreferences(suiteName: suiteName)
        prefs.focusDurationMinutes = 45
        XCTAssertEqual(prefs.focusDurationMinutes, 45)
    }

    // MARK: - Persistence across instances

    func test_focusDurationMinutes_persistsAcrossInstances() {
        let first = MINDPreferences(suiteName: suiteName)
        first.focusDurationMinutes = 90

        let second = MINDPreferences(suiteName: suiteName)
        XCTAssertEqual(second.focusDurationMinutes, 90,
                       "Same suite name must read back the same value — proves UserDefaults write actually happened")
    }

    func test_auditNotificationsEnabled_persistsAcrossInstances() {
        let first = MINDPreferences(suiteName: suiteName)
        first.auditNotificationsEnabled = false

        let second = MINDPreferences(suiteName: suiteName)
        XCTAssertFalse(second.auditNotificationsEnabled)
    }

    func test_sentryDSN_persistsAcrossInstances_andTrimsWhitespace() {
        let first = MINDPreferences(suiteName: suiteName)
        first.sentryDSN = "  https://abc@sentry.io/123  "

        let second = MINDPreferences(suiteName: suiteName)
        XCTAssertEqual(second.sentryDSN, "https://abc@sentry.io/123",
                       "Whitespace around pasted DSNs must be stripped before persisting")
    }

    // MARK: - Static accessors used by non-Observable callers

    func test_currentFocusDurationMinutes_returns25_whenNeverSet() {
        XCTAssertEqual(
            MINDPreferences.currentFocusDurationMinutes(suiteName: suiteName),
            25
        )
    }

    func test_currentFocusDurationMinutes_readsPersistedValue() {
        let prefs = MINDPreferences(suiteName: suiteName)
        prefs.focusDurationMinutes = 60
        XCTAssertEqual(
            MINDPreferences.currentFocusDurationMinutes(suiteName: suiteName),
            60
        )
    }

    func test_currentAuditNotificationsEnabled_defaultsToTrue_whenNeverSet() {
        XCTAssertTrue(
            MINDPreferences.currentAuditNotificationsEnabled(suiteName: suiteName)
        )
    }

    func test_currentAuditNotificationsEnabled_readsExplicitFalse() {
        let prefs = MINDPreferences(suiteName: suiteName)
        prefs.auditNotificationsEnabled = false
        XCTAssertFalse(
            MINDPreferences.currentAuditNotificationsEnabled(suiteName: suiteName)
        )
    }

    func test_currentSentryDSN_returnsNil_whenEmpty() {
        XCTAssertNil(MINDPreferences.currentSentryDSN(suiteName: suiteName))
    }

    func test_currentSentryDSN_returnsValue_whenSet() {
        let prefs = MINDPreferences(suiteName: suiteName)
        prefs.sentryDSN = "https://x@sentry.io/y"
        XCTAssertEqual(
            MINDPreferences.currentSentryDSN(suiteName: suiteName),
            "https://x@sentry.io/y"
        )
    }

    func test_currentSentryDSN_returnsNil_whenOnlyWhitespace() {
        let prefs = MINDPreferences(suiteName: suiteName)
        prefs.sentryDSN = "   "
        XCTAssertNil(
            MINDPreferences.currentSentryDSN(suiteName: suiteName),
            "All-whitespace DSN must be treated as unconfigured so Sentry stays off"
        )
    }

    // MARK: - Presets

    func test_focusDurationPresets_areMonotonicallyIncreasing() {
        let presets = MINDPreferences.focusDurationPresets
        XCTAssertEqual(presets, presets.sorted(),
                       "UI relies on left-to-right ascending order in the duration picker")
    }

    func test_focusDurationPresets_allWithinClampRange() {
        for p in MINDPreferences.focusDurationPresets {
            XCTAssertGreaterThanOrEqual(p, 5)
            XCTAssertLessThanOrEqual(p, 180)
        }
    }
}
