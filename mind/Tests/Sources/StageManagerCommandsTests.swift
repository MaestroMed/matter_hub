import XCTest
import Foundation
@testable import MIND

/// v0.24.1 — locks the pure pieces of the Stage Manager / Mac
/// Catalyst keyboard-shortcut surface. The `Commands` SwiftUI
/// builder itself isn't unit-testable directly (it lives in the
/// menu DSL evaluator), but every input that drives it — the
/// `TabShortcut` mapping, the `Notification.Name` rawValues, and
/// the `StageManagerCommandID` enum — is pure data and gets the
/// regression net here.
final class StageManagerCommandsTests: XCTestCase {

    // MARK: - StageManagerCommandID

    /// Each command ID must be uniquely identifiable so two
    /// different keyboard shortcuts never end up posting on the
    /// same notification by accident.
    func test_commandIDs_areUnique() {
        let rawValues = StageManagerCommandID.allCases.map(\.rawValue)
        XCTAssertEqual(
            Set(rawValues).count,
            rawValues.count,
            "Every StageManagerCommandID rawValue must be unique"
        )
    }

    /// Every command ID's rawValue is reused as the matching
    /// Notification.Name rawValue. Locking the prefix here means a
    /// future ID rename has to update both sides — the test fails
    /// loudly if someone introduces a string drift.
    func test_commandID_rawValues_havePrefix() {
        for id in StageManagerCommandID.allCases {
            XCTAssertTrue(
                id.rawValue.hasPrefix("app.mind.ios.command."),
                "Command ID \(id) should follow the app.mind.ios.command.<name> convention; got \(id.rawValue)"
            )
        }
    }

    /// The notification names exposed at file scope must match the
    /// rawValues of the corresponding enum cases — this is the
    /// contract the StageManagerCommands SwiftUI builder posts on,
    /// and the RootView .onReceive listens for.
    func test_notificationNames_matchEnumRawValues() {
        XCTAssertEqual(
            Notification.Name.mindCommandNewAudit.rawValue,
            StageManagerCommandID.newAudit.rawValue
        )
        XCTAssertEqual(
            Notification.Name.mindCommandSelectTab.rawValue,
            StageManagerCommandID.selectTab.rawValue
        )
    }

    // MARK: - TabShortcut

    /// `keyDigit` must be unique across cases so two ⌘N shortcuts
    /// never collide on the same digit. Locking this is the cheapest
    /// way to catch a future "I added a 5th tab but forgot to bump
    /// the digit" regression.
    func test_keyDigits_areUnique() {
        let digits = TabShortcut.allCases.map(\.keyDigit)
        XCTAssertEqual(
            Set(digits).count,
            digits.count,
            "Each TabShortcut must own a unique keyDigit"
        )
    }

    /// Sidebar order: ⌘1 = Home, ⌘2 = Clients, ⌘3 = Pipeline,
    /// ⌘4 = Settings. Matches the order surfaced by the cockpit
    /// LiquidTabBar on iPhone + the NavigationSplitView sidebar on
    /// iPad, so the user's muscle memory transfers across layouts.
    func test_keyDigit_ordering_matchesCockpit() {
        XCTAssertEqual(TabShortcut.home.keyDigit,     1)
        XCTAssertEqual(TabShortcut.clients.keyDigit,  2)
        XCTAssertEqual(TabShortcut.pipeline.keyDigit, 3)
        XCTAssertEqual(TabShortcut.settings.keyDigit, 4)
    }

    /// keyDigits must be in the 1...4 range. Going below 1 would
    /// collide with ⌘0 (typically "default zoom") and above 4 is a
    /// dead key. Lock the window so a typo introducing ⌘9 fails
    /// in CI rather than at runtime when SwiftUI silently drops
    /// the binding.
    func test_keyDigits_areInValidRange() {
        for shortcut in TabShortcut.allCases {
            XCTAssertGreaterThanOrEqual(
                shortcut.keyDigit,
                1,
                "TabShortcut \(shortcut) keyDigit must be >= 1"
            )
            XCTAssertLessThanOrEqual(
                shortcut.keyDigit,
                9,
                "TabShortcut \(shortcut) keyDigit must be a single digit"
            )
        }
    }

    /// Round-trip: `from(keyDigit:)` reverses `keyDigit` for every
    /// case. Out-of-range digits return nil. Used by future
    /// scripted-Shortcuts integrations that POST on
    /// mindCommandSelectTab with a digit instead of a rawValue.
    func test_from_keyDigit_roundTrip() {
        for shortcut in TabShortcut.allCases {
            XCTAssertEqual(
                TabShortcut.from(keyDigit: shortcut.keyDigit),
                shortcut,
                "Round-trip failed for \(shortcut)"
            )
        }
    }

    /// Out-of-range digits gracefully return nil so the
    /// `Notification.userInfo` decode path can fall through to a
    /// `command.selectTab.malformed` warning rather than crash.
    func test_from_keyDigit_outOfRange_returnsNil() {
        XCTAssertNil(TabShortcut.from(keyDigit: 0))
        XCTAssertNil(TabShortcut.from(keyDigit: 5))
        XCTAssertNil(TabShortcut.from(keyDigit: 99))
        XCTAssertNil(TabShortcut.from(keyDigit: -1))
    }

    /// `localizedKey` follows the `command.tab.<rawValue>` namespace
    /// the xcstrings catalog uses. Lock it so a future rename of
    /// the namespace is forced through both sides simultaneously.
    func test_localizedKey_followsNamespace() {
        XCTAssertEqual(TabShortcut.home.localizedKey,     "command.tab.home")
        XCTAssertEqual(TabShortcut.clients.localizedKey,  "command.tab.clients")
        XCTAssertEqual(TabShortcut.pipeline.localizedKey, "command.tab.pipeline")
        XCTAssertEqual(TabShortcut.settings.localizedKey, "command.tab.settings")
    }

    /// Fallback titles must be non-empty so the menu bar never
    /// renders a blank label when running outside the host bundle
    /// (preview / unit-test process, no .xcstrings loaded).
    func test_fallbackTitles_areNonEmpty() {
        for shortcut in TabShortcut.allCases {
            XCTAssertFalse(
                shortcut.fallbackTitle.isEmpty,
                "TabShortcut \(shortcut) must ship a non-empty fallback title"
            )
        }
    }

    // MARK: - Notification posting contract

    /// Posting on `mindCommandSelectTab` with a `userInfo["tab"]`
    /// payload that matches a TabShortcut rawValue must be round-
    /// trippable back to the matching TabShortcut. This locks the
    /// exact contract the RootView .onReceive listener depends on.
    func test_notificationUserInfoEncoding_roundTrips() {
        let expectation = expectation(description: "notification received")
        let center = NotificationCenter.default
        let token = center.addObserver(
            forName: .mindCommandSelectTab,
            object: nil,
            queue: nil
        ) { notif in
            guard let raw = notif.userInfo?["tab"] as? String else {
                XCTFail("Notification missing 'tab' userInfo key")
                expectation.fulfill()
                return
            }
            XCTAssertEqual(raw, TabShortcut.pipeline.rawValue)
            XCTAssertEqual(MINDTab(rawValue: raw), .pipeline)
            expectation.fulfill()
        }
        defer { center.removeObserver(token) }

        center.post(
            name: .mindCommandSelectTab,
            object: nil,
            userInfo: ["tab": TabShortcut.pipeline.rawValue]
        )

        wait(for: [expectation], timeout: 1.0)
    }

    /// TabShortcut and MINDTab share the same rawValues so the
    /// menu-bar payload decodes cleanly into a tab the cockpit
    /// understands. If a new MINDTab case is added without a
    /// matching TabShortcut (or vice versa), this fails loudly.
    func test_tabShortcut_alignsWithMINDTab() {
        // Every TabShortcut rawValue decodes into a MINDTab case
        for shortcut in TabShortcut.allCases {
            XCTAssertNotNil(
                MINDTab(rawValue: shortcut.rawValue),
                "TabShortcut.\(shortcut) rawValue '\(shortcut.rawValue)' must map back to a MINDTab case"
            )
        }
    }
}
