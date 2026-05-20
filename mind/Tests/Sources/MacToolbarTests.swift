import XCTest
import Foundation
@testable import MIND

/// v1.0-alpha.12 — Locks the pure `MacToolbarAction` table. The
/// Catalyst toolbar surface ships four actions (Lead inbox / Audit /
/// Bootstrap / Refresh) and each one must carry a localized title,
/// an SF Symbol name, and a unique notification name. These tests
/// catch the drift where someone adds a new action but forgets one
/// of the three companion fields — the toolbar would render with a
/// missing label or a missing icon, which is exactly the kind of
/// "looks broken on Mac" regression we want to fail loudly in CI.
final class MacToolbarTests: XCTestCase {

    // MARK: - Action table coverage

    /// Every action has a non-empty localized key + a non-empty
    /// system image. A blank label would render a phantom-spacing
    /// toolbar item; a blank system image would render nothing at
    /// all in the bezel.
    func test_allActions_haveTitleAndSystemImage() {
        for action in MacToolbarAction.allCases {
            XCTAssertFalse(
                action.localizedKey.isEmpty,
                "MacToolbarAction.\(action) must ship a localizedKey"
            )
            XCTAssertFalse(
                action.systemImage.isEmpty,
                "MacToolbarAction.\(action) must ship a systemImage"
            )
            XCTAssertFalse(
                action.fallbackTitle.isEmpty,
                "MacToolbarAction.\(action) must ship a fallback title for unit-test bundles"
            )
        }
    }

    /// Each `localizedKey` follows the `toolbar.<rawCaseName>`
    /// namespace. Same convention test as `MacKeyboardShortcutsTests`
    /// uses for the `menu.shortcuts.*` keys — keeps a future addition
    /// honest about which xcstrings catalog section it belongs to.
    func test_localizedKeys_followToolbarNamespace() {
        for action in MacToolbarAction.allCases {
            XCTAssertTrue(
                action.localizedKey.hasPrefix("toolbar."),
                "MacToolbarAction.\(action) localizedKey must sit under toolbar.*; got \(action.localizedKey)"
            )
        }
    }

    /// Every action's `rawValue` follows the
    /// `app.mind.ios.command.<name>` notification namespace. The
    /// rawValue doubles as the `Notification.Name.rawValue`, so a
    /// drift here would create two shortcuts on the same notification
    /// channel silently — exactly the kind of bug a unit test exists
    /// to catch.
    func test_rawValues_followCommandNamespace() {
        for action in MacToolbarAction.allCases {
            XCTAssertTrue(
                action.rawValue.hasPrefix("app.mind.ios.command."),
                "MacToolbarAction.\(action) rawValue must sit under app.mind.ios.command.*; got \(action.rawValue)"
            )
        }
    }

    /// The notification names exposed at file scope must match the
    /// rawValues of the corresponding enum cases — same contract the
    /// existing StageManagerCommands surface has.
    func test_notificationNames_matchRawValues() {
        XCTAssertEqual(
            MacToolbarAction.leads.notificationName.rawValue,
            MacToolbarAction.leads.rawValue
        )
        XCTAssertEqual(
            MacToolbarAction.bootstrap.notificationName.rawValue,
            MacToolbarAction.bootstrap.rawValue
        )
        XCTAssertEqual(
            MacToolbarAction.audit.notificationName.rawValue,
            MacToolbarAction.audit.rawValue
        )
        XCTAssertEqual(
            MacToolbarAction.refresh.notificationName.rawValue,
            MacToolbarAction.refresh.rawValue
        )
    }

    /// Notification names across all actions are unique. Same
    /// uniqueness contract `MacKeyboardShortcutsTests` enforces on
    /// the shortcut catalog — duplicate names mean two unrelated
    /// listeners would react to the same notification.
    func test_notificationNames_areUnique() {
        let names = MacToolbarAction.allCases.map(\.notificationName.rawValue)
        XCTAssertEqual(
            Set(names).count,
            names.count,
            "Every MacToolbarAction must own a unique Notification.Name"
        )
    }
}
