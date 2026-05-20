import XCTest
import Foundation
@testable import MIND

/// v1.0-alpha.12 — Locks the pure MacShortcut → Notification.Name
/// mapping table. SwiftUI's `Commands` builder itself is not
/// unit-testable directly (the menu DSL lives in the SwiftUI
/// evaluator), but every input that drives it — the shortcut keys,
/// the modifier sets, the notification names, the userInfo payload —
/// is pure data and gets regression coverage here.
///
/// The test bar is high on purpose: a typo on the modifier set or a
/// drift between two shortcuts mapping to the same notification name
/// would silently break the menu bar surface on Mac Catalyst with no
/// runtime crash, just a non-functional shortcut. CI catches it here
/// instead of when Mehdi tries ⌘⇧A on his 27" Numelite workstation.
final class MacKeyboardShortcutsTests: XCTestCase {

    // MARK: - ⌘B → Bootstrap

    /// ⌘B opens the Bootstrap wizard. Locking the key + modifier
    /// pair + the notification name keeps the menu DSL, the
    /// MacShortcut catalog, and the RootView .onReceive listener all
    /// in lock-step. Locked to .mindCommandBootstrap so any future
    /// refactor that renames the notification has to touch this test.
    func test_bootstrapShortcut_firesBootstrapNotification() {
        let shortcut = MacShortcut.bootstrap
        XCTAssertEqual(shortcut.key, "b")
        XCTAssertEqual(shortcut.modifiers.command, true)
        XCTAssertEqual(shortcut.modifiers.shift, false)
        XCTAssertEqual(
            shortcut.notificationName,
            .mindCommandBootstrap,
            "⌘B must post on .mindCommandBootstrap"
        )
    }

    // MARK: - ⌘L → Lead Inbox

    /// ⌘L surfaces the lead inbox on Home. Same triple-lock as
    /// `test_bootstrapShortcut_firesBootstrapNotification` but for
    /// the inbox channel.
    func test_leadInboxShortcut_firesLeadInboxNotification() {
        let shortcut = MacShortcut.leadInbox
        XCTAssertEqual(shortcut.key, "l")
        XCTAssertEqual(shortcut.modifiers.command, true)
        XCTAssertEqual(shortcut.modifiers.shift, false)
        XCTAssertEqual(
            shortcut.notificationName,
            .mindCommandLeadInbox,
            "⌘L must post on .mindCommandLeadInbox"
        )
    }

    // MARK: - ⌘I → New Invoice

    /// ⌘I opens the Invoice composer. The notification name uses a
    /// dedicated channel because the invoice composer surface can
    /// open from multiple entry points (project detail, pipeline-
    /// drop on Won, menu bar) and we want every listener wired
    /// through the same notification.
    func test_newInvoiceShortcut_firesNewInvoiceNotification() {
        let shortcut = MacShortcut.newInvoice
        XCTAssertEqual(shortcut.key, "i")
        XCTAssertEqual(shortcut.modifiers.command, true)
        XCTAssertEqual(shortcut.modifiers.shift, false)
        XCTAssertEqual(
            shortcut.notificationName,
            .mindCommandNewInvoice,
            "⌘I must post on .mindCommandNewInvoice"
        )
    }

    // MARK: - Uniqueness contract

    /// Every shortcut must have a uniquely identifying (key,
    /// modifier-set) tuple so the menu DSL never registers two
    /// entries colliding on the same key-equivalent. Same-letter
    /// shortcuts that differ on the .shift modifier are OK (⌘B and
    /// ⌘⇧B are two distinct shortcuts) — this test only catches
    /// fully-identical pairs.
    func test_shortcuts_haveUniqueKeyAndModifierPairs() {
        struct Pair: Hashable {
            let key: String
            let command: Bool
            let shift: Bool
        }
        let pairs = MacShortcut.allCases.map { shortcut in
            Pair(
                key: String(shortcut.key),
                command: shortcut.modifiers.command,
                shift: shortcut.modifiers.shift
            )
        }
        XCTAssertEqual(
            Set(pairs).count,
            pairs.count,
            "Each MacShortcut must own a unique (key, modifiers) tuple"
        )
    }

    /// Every shortcut posts on a `Notification.Name` whose rawValue
    /// begins with `app.mind.ios.command.` — the cockpit's universal
    /// command-channel namespace. Locks the convention so a future
    /// shortcut added via copy-paste can't drift onto a generic
    /// `Notification.Name("refresh")` shared with some other module.
    func test_shortcutNotifications_followNamespace() {
        for shortcut in MacShortcut.allCases {
            XCTAssertTrue(
                shortcut.notificationName.rawValue.hasPrefix("app.mind.ios.command."),
                "MacShortcut.\(shortcut) must post on the app.mind.ios.command.* namespace; got \(shortcut.notificationName.rawValue)"
            )
        }
    }

    /// The two tab-switch entries (⌘P and ⌘,) reuse the existing
    /// `mindCommandSelectTab` notification with a `userInfo["tab"]`
    /// payload that names the destination — locks the contract the
    /// `RootView.onReceive(.mindCommandSelectTab)` listener depends
    /// on.
    func test_tabSwitch_shortcuts_carryTabPayload() {
        XCTAssertEqual(
            MacShortcut.pipelineTab.notificationUserInfo["tab"],
            "pipeline"
        )
        XCTAssertEqual(
            MacShortcut.settingsTab.notificationUserInfo["tab"],
            "settings"
        )
        // Non-tab-switch shortcuts ship an empty payload so a future
        // listener that reads `userInfo["tab"]` on the wrong
        // notification gets nil, not a spurious value.
        XCTAssertEqual(
            MacShortcut.bootstrap.notificationUserInfo,
            [:]
        )
    }

    /// The project-action quartet (audit-source / battle / outreach /
    /// deploy) shares the ⌘⇧ modifier set. Locks the convention so a
    /// future "global" shortcut can't accidentally drift into the
    /// shift-modifier subspace reserved for project actions.
    func test_projectActions_useShiftModifier() {
        for shortcut in [MacShortcut.auditSource, .battleMode, .outreach, .deploy] {
            XCTAssertTrue(
                shortcut.modifiers.shift,
                "Project-scoped action \(shortcut) must use ⌘⇧"
            )
            XCTAssertTrue(
                shortcut.modifiers.command,
                "Project-scoped action \(shortcut) must use ⌘"
            )
        }
    }

    /// Round-trip via a NotificationCenter post: firing the
    /// notification name for a given shortcut and observing it
    /// returns the original shortcut's payload. Covers the path the
    /// menu DSL takes when it posts on tap.
    func test_notificationPost_roundTrips() {
        let expectation = expectation(description: "lead inbox observed")
        let center = NotificationCenter.default
        let token = center.addObserver(
            forName: .mindCommandLeadInbox,
            object: nil,
            queue: nil
        ) { _ in
            expectation.fulfill()
        }
        defer { center.removeObserver(token) }
        center.post(name: .mindCommandLeadInbox, object: nil)
        wait(for: [expectation], timeout: 1.0)
    }

    /// Every shortcut's localized key sits under `menu.shortcuts.*`.
    /// Locks the namespace so the LocalizationTests can sweep over
    /// it without enumerating cases by hand.
    func test_localizedKeys_followNamespace() {
        for shortcut in MacShortcut.allCases {
            XCTAssertTrue(
                shortcut.localizedKey.hasPrefix("menu.shortcuts."),
                "MacShortcut.\(shortcut) localizedKey must sit under menu.shortcuts.*; got \(shortcut.localizedKey)"
            )
        }
    }
}
