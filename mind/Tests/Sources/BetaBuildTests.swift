import XCTest
@testable import Settings

/// v0.20 — Locks the `SettingsView.isBetaVersion(_:)` pure helper that
/// drives every beta-only surface in the app: the BETA badge in
/// Settings → About, the "Beta" section with the TestFlight feedback
/// + join rows, and the dismissible welcome banner on HomeView.
///
/// The contract:
///   - any pre-1.0 version string (`0.20.0`, `0.999.999`, `0.0.1`,
///     `0.5.0`) → `true`
///   - any 1.x or 2.x version string → `false`
///   - malformed input (missing patch, non-numeric, empty, fallback
///     `"—"`) → `true` so dev / preview / test bundles still surface
///     the beta UI for inspection
///
/// The helper is a static, pure, side-effect-free version compare —
/// no `Bundle.main` mocking required.
final class BetaBuildTests: XCTestCase {

    // MARK: Pre-1.0 versions ship as betas

    func test_isBetaVersion_zeroFiveZero_returnsTrue() {
        XCTAssertTrue(SettingsView.isBetaVersion("0.5.0"))
    }

    func test_isBetaVersion_zeroPointZeroOne_returnsTrue() {
        XCTAssertTrue(SettingsView.isBetaVersion("0.0.1"))
    }

    func test_isBetaVersion_zeroNineNineNine_returnsTrue() {
        XCTAssertTrue(SettingsView.isBetaVersion("0.999.999"))
    }

    func test_isBetaVersion_currentBuildVersion_returnsTrue() {
        // Lock the version currently in Project.swift so a bump to a
        // pre-1.0 minor (0.20, 0.21, …) doesn't accidentally flip the
        // beta UI off mid-development.
        XCTAssertTrue(SettingsView.isBetaVersion("0.20.0"))
    }

    // MARK: 1.x and above ship as stable

    func test_isBetaVersion_oneZeroZero_returnsFalse() {
        XCTAssertFalse(SettingsView.isBetaVersion("1.0.0"))
    }

    func test_isBetaVersion_oneFiveZero_returnsFalse() {
        XCTAssertFalse(SettingsView.isBetaVersion("1.5.0"))
    }

    func test_isBetaVersion_twoZeroZero_returnsFalse() {
        XCTAssertFalse(SettingsView.isBetaVersion("2.0.0"))
    }

    // MARK: Malformed input defaults to true (safer for dev / test)

    func test_isBetaVersion_emptyString_returnsTrue() {
        XCTAssertTrue(SettingsView.isBetaVersion(""))
    }

    func test_isBetaVersion_emDashFallback_returnsTrue() {
        // `SettingsView.appVersion` returns `"—"` when Info.plist is
        // missing the key, e.g. in preview / test bundles.
        XCTAssertTrue(SettingsView.isBetaVersion("—"))
    }

    func test_isBetaVersion_missingPatch_returnsTrueWhenMajorIsZero() {
        // "0.5" lacks a patch component but its major is still zero,
        // so the build is unambiguously a beta.
        XCTAssertTrue(SettingsView.isBetaVersion("0.5"))
    }

    func test_isBetaVersion_majorOnlyZero_returnsTrue() {
        // "0" — pathological, but still pre-1.0.
        XCTAssertTrue(SettingsView.isBetaVersion("0"))
    }

    func test_isBetaVersion_nonNumericMajor_returnsTrue() {
        // Defensive: if someone ships a garbage string, default to
        // showing the beta UI rather than hiding it silently.
        XCTAssertTrue(SettingsView.isBetaVersion("alpha"))
    }
}
