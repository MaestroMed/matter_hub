import XCTest
import Foundation
@testable import MIND

/// v1.0-alpha.12 — Locks the `@SceneStorage` key namespace used by
/// Mac Catalyst window restoration. SwiftUI's `@SceneStorage` is
/// keyed by string; collisions with other `@AppStorage` or
/// `@SceneStorage` keys elsewhere in the codebase silently overwrite
/// each other's state on restore. This test centralises every key
/// MIND uses so a future addition forces the new entry through the
/// namespace check before it can ship.
final class MacSceneStorageTests: XCTestCase {

    /// The four documented keys (selected tab, selected project ID,
    /// selected lead ID, sidebar visibility) must all be declared.
    /// Locks the v1.0-alpha.12 contract — removing one without a
    /// follow-up SceneStorage migration would break the restore
    /// experience for users with existing windows.
    func test_allKeys_areDeclared() {
        XCTAssertEqual(
            MacSceneStorageKey.allKeys.count,
            4,
            "MacSceneStorageKey.allKeys must enumerate exactly 4 keys (selectedTab, selectedProjectID, selectedLeadID, sidebarVisibility)"
        )
        XCTAssertTrue(MacSceneStorageKey.allKeys.contains(MacSceneStorageKey.selectedTab))
        XCTAssertTrue(MacSceneStorageKey.allKeys.contains(MacSceneStorageKey.selectedProjectID))
        XCTAssertTrue(MacSceneStorageKey.allKeys.contains(MacSceneStorageKey.selectedLeadID))
        XCTAssertTrue(MacSceneStorageKey.allKeys.contains(MacSceneStorageKey.sidebarVisibility))
    }

    /// Every `@SceneStorage` key MIND ships sits under
    /// `mind.scene.*`. Same namespace audit pattern as the
    /// command catalog — keeps the restore-side state owned by a
    /// single, audit-able prefix.
    func test_allKeys_followNamespace() {
        for key in MacSceneStorageKey.allKeys {
            XCTAssertTrue(
                key.hasPrefix("mind.scene."),
                "@SceneStorage key '\(key)' must sit under mind.scene.*"
            )
        }
    }

    /// Keys must be unique. Two `@SceneStorage` properties with the
    /// same key silently share state — the property declared last
    /// wins, the other one becomes a read-only mirror. Easy to ship,
    /// hard to debug, exactly the regression class this test exists
    /// to lock against.
    func test_allKeys_areUnique() {
        XCTAssertEqual(
            Set(MacSceneStorageKey.allKeys).count,
            MacSceneStorageKey.allKeys.count,
            "Every @SceneStorage key must be unique"
        )
    }

    // MARK: - Dock badge

    /// `MacDockBadge.displayCount(forNewLeads:)` clamps negative
    /// inputs to 0 (a `setBadgeCount(-1)` would render an "X" on the
    /// dock, which is the iOS convention for "infinite") and caps
    /// the upper end at 99 so a webhook flood never renders a
    /// nonsense "1247" on the dock icon.
    func test_dockBadge_displayCount_clampsToValidRange() {
        XCTAssertEqual(MacDockBadge.displayCount(forNewLeads: -5), 0)
        XCTAssertEqual(MacDockBadge.displayCount(forNewLeads: 0), 0)
        XCTAssertEqual(MacDockBadge.displayCount(forNewLeads: 1), 1)
        XCTAssertEqual(MacDockBadge.displayCount(forNewLeads: 12), 12)
        XCTAssertEqual(MacDockBadge.displayCount(forNewLeads: 99), 99)
        XCTAssertEqual(MacDockBadge.displayCount(forNewLeads: 100), 99)
        XCTAssertEqual(MacDockBadge.displayCount(forNewLeads: 9_999), 99)
    }
}
