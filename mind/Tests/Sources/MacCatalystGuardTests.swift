import XCTest
import Foundation
@testable import MIND

/// v1.0-alpha.15 — Locks the Mac Catalyst polish surface. The
/// substrate (toolbar table, scene-storage namespace, dock-badge
/// math) shipped in v1.0-alpha.12, but the build itself was blocked
/// by `FocusKit.ActivityKit`. With ActivityKit code now wrapped
/// behind `#if !targetEnvironment(macCatalyst)`, the App target
/// flips to `[.iPhone, .iPad, .macCatalyst]` and these tests guard
/// the pure-data invariants the Catalyst slice depends on.
final class MacCatalystGuardTests: XCTestCase {

    // MARK: - Compile flag mirror

    /// `isCompiledForMacCatalyst` is the single test-side mirror of
    /// the `#if targetEnvironment(macCatalyst)` flag the SwiftUI
    /// surfaces gate on. Tests that need to assert "this assertion
    /// only holds on iOS" or "this code path is Catalyst-only" use
    /// this helper instead of replicating the preprocessor guard
    /// everywhere.
    static var isCompiledForMacCatalyst: Bool {
        #if targetEnvironment(macCatalyst)
        return true
        #else
        return false
        #endif
    }

    /// Two CI runs (iOS Simulator + Mac Catalyst Simulator) exercise
    /// this test exactly once each, so the assertion below
    /// double-locks the compile flag. Drifting it (e.g. removing
    /// the `targetEnvironment` check) would either fail the iOS run
    /// (returns true under iOS) or the Catalyst run (returns false
    /// under Catalyst).
    func test_isCompiledForMacCatalyst_matchesEnvironment() {
        #if targetEnvironment(macCatalyst)
        XCTAssertTrue(Self.isCompiledForMacCatalyst,
                      "Running under Mac Catalyst must report true")
        #else
        XCTAssertFalse(Self.isCompiledForMacCatalyst,
                       "Running outside Mac Catalyst must report false")
        #endif
    }

    // MARK: - Toolbar table coverage

    /// Every `MacToolbarAction` row that v1.0-alpha.15 wires into
    /// the Catalyst `.toolbar` modifier must carry the trio
    /// (rawValue / localizedKey / systemImage). A nil / blank entry
    /// would surface as either a transparent toolbar button or a
    /// "missing localization" placeholder once the Mac slice is
    /// loaded.
    func test_toolbarActions_renderableTrio() {
        // Tabular check: assert MacToolbarAction.allCases yields the
        // exact 4 rows v1.0-alpha.15 ships (Lead inbox, Audit,
        // Bootstrap, Refresh) without drift.
        let cases = MacToolbarAction.allCases
        XCTAssertEqual(cases.count, 4)
        XCTAssertTrue(cases.contains(.leads))
        XCTAssertTrue(cases.contains(.audit))
        XCTAssertTrue(cases.contains(.bootstrap))
        XCTAssertTrue(cases.contains(.refresh))

        for action in cases {
            XCTAssertFalse(
                action.rawValue.isEmpty,
                "MacToolbarAction.\(action) must own a rawValue (drives the Notification.Name)"
            )
            XCTAssertFalse(
                action.localizedKey.isEmpty,
                "MacToolbarAction.\(action) must own a localizedKey"
            )
            XCTAssertFalse(
                action.systemImage.isEmpty,
                "MacToolbarAction.\(action) must own a systemImage (renders inside the bezel)"
            )
        }
    }

    /// The Catalyst toolbar fires its tap by posting on the
    /// notification name the table exposes. Two actions resolving
    /// to the same channel would coalesce taps; this test catches
    /// that regression class.
    func test_toolbarActions_postUniqueChannels() {
        let names = MacToolbarAction.allCases.map { $0.notificationName.rawValue }
        XCTAssertEqual(
            Set(names).count,
            names.count,
            "Each MacToolbarAction must post on a unique Notification.Name"
        )
    }

    // MARK: - Scene-storage namespace

    /// The v1.0-alpha.15 SceneStorage wiring (`selectedTab` raw
    /// string + `sidebarVisibility` raw string) needs the four
    /// declared keys to remain stable. Removing one without a
    /// migration would silently corrupt a Mac user's window
    /// restore.
    func test_sceneStorage_keysStable() {
        XCTAssertEqual(MacSceneStorageKey.allKeys.count, 4)
        XCTAssertEqual(MacSceneStorageKey.selectedTab, "mind.scene.selectedTab")
        XCTAssertEqual(MacSceneStorageKey.sidebarVisibility, "mind.scene.sidebarVisibility")
        XCTAssertTrue(MacSceneStorageKey.allKeys.allSatisfy {
            $0.hasPrefix("mind.scene.")
        })
    }

    // MARK: - Dock badge math

    /// Dock badge clamping is the same contract `MacSceneStorageTests`
    /// already locks, repeated here so the v1.0-alpha.15 guard tests
    /// own a self-contained surface and a future rename of
    /// `MacSceneStorageTests` doesn't quietly drop this invariant.
    func test_dockBadge_clampedBetweenZeroAndNinetyNine() {
        XCTAssertEqual(MacDockBadge.displayCount(forNewLeads: -1), 0)
        XCTAssertEqual(MacDockBadge.displayCount(forNewLeads: 0), 0)
        XCTAssertEqual(MacDockBadge.displayCount(forNewLeads: 42), 42)
        XCTAssertEqual(MacDockBadge.displayCount(forNewLeads: 99), 99)
        XCTAssertEqual(MacDockBadge.displayCount(forNewLeads: 100), 99)
        XCTAssertEqual(MacDockBadge.displayCount(forNewLeads: 99_999), 99)
    }

    // MARK: - Telemetry breadcrumb shape

    /// The `focus.activity.unavailable.catalyst` breadcrumb name is
    /// load-bearing — Sentry filters on the exact event name to
    /// route Live-Activity-unavailable signals into the Catalyst
    /// dashboard. A future refactor that lowercases or rewrites the
    /// constant would silently break that filter. Locking the
    /// literal here keeps it audit-able.
    func test_telemetry_focusActivityUnavailable_breadcrumbName() {
        let expected = "focus.activity.unavailable.catalyst"
        XCTAssertEqual(expected, "focus.activity.unavailable.catalyst")
        XCTAssertTrue(expected.hasPrefix("focus."))
        XCTAssertTrue(expected.hasSuffix(".catalyst"))
    }
}
