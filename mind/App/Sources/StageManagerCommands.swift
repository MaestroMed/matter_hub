import SwiftUI
import GraphCore

// v0.24.1 — iPad Stage Manager polish
//
// This file bundles three concerns that together make MIND behave like
// a proper desktop-class app when the user pulls it into a Stage
// Manager tile or runs it on Mac Catalyst / iPad Pro keyboard:
//
//   1. `StageManagerCommandID` — stable string identifiers for every
//      keyboard-driven action surfaced through the menu bar. Each ID
//      is the string payload of a `Notification.Name`, so the
//      `Commands` builder and the `RootView` listeners stay in lock-
//      step through a single source of truth instead of stringly-
//      duplicated names.
//
//   2. `TabShortcut` — pure mapping between ⌘1 / ⌘2 / … and the
//      MINDTab the user expects to land on. Pure value with `allCases`
//      so the unit tests can lock the ordering against the sidebar
//      contract in `MINDTab.allCasesOrdered`.
//
//   3. `StageManagerCommands` — the `Commands` builder mounted via
//      `WindowGroup { … }.commands { StageManagerCommands() }` in
//      `MINDApp.swift`. Posts the matching notification on every
//      menu pick so `RootView` / `HomeView` (the owners of
//      `selection` / `isAuditing`) can react without `Commands`
//      having to read the @State directly (Commands runs in a
//      separate evaluation pass; passing a Binding in is brittle
//      and `@MainActor` host state isn't reachable from inside the
//      menu DSL).

/// String identifiers for every command exposed through the iPad /
/// Mac Catalyst menu bar in v0.24.1. The raw value of each case is
/// also the `Notification.Name.rawValue` posted when the command
/// fires, so any new command added here automatically gets a stable
/// notification name without duplication.
public enum StageManagerCommandID: String, CaseIterable, Sendable {
    /// ⌘N — opens a fresh Audit form on the Home tab. The cockpit's
    /// primary new-item action: every freelancer interaction starts
    /// from an audit, so ⌘N maps to the audit sheet rather than the
    /// pre-pivot "new note" gesture.
    case newAudit = "app.mind.ios.command.newAudit"

    /// ⌘1 / ⌘2 / ⌘3 / ⌘4 — switches the selected sidebar destination.
    /// The `userInfo["tab"]` payload carries the MINDTab raw value.
    case selectTab = "app.mind.ios.command.selectTab"
}

extension Notification.Name {
    /// ⌘N — Audit sheet. Listened to by `RootView` to flip the
    /// selected tab to `.home` AND by `HomeView` to flip
    /// `isAuditing = true` so the sheet presents.
    static let mindCommandNewAudit = Notification.Name(StageManagerCommandID.newAudit.rawValue)

    /// ⌘1 / ⌘2 / ⌘3 / ⌘4 — switch sidebar destination.
    /// `userInfo["tab"]` carries the MINDTab raw value (`home`,
    /// `clients`, `pipeline`, `settings`).
    static let mindCommandSelectTab = Notification.Name(StageManagerCommandID.selectTab.rawValue)
}

/// Maps a key-equivalent to the MINDTab the user wants to surface.
/// Pure, deterministic, fully covered by unit tests. The raw string
/// matches the rawValue of the corresponding MINDTab case so the
/// `userInfo["tab"]` payload posted by `StageManagerCommands` flows
/// cleanly through `Notification.userInfo` (which only carries
/// plist-encodable types).
public enum TabShortcut: String, CaseIterable, Sendable {
    case home, clients, pipeline, settings

    /// Stable ⌘-N digit. Matches the sidebar order in
    /// `MINDTab.allCasesOrdered` (Home, Clients, Pipeline,
    /// Settings). Keeping this 1-indexed instead of 0-indexed
    /// because that's what desktop apps do (⌘1 = first tab, not
    /// "the zeroth one").
    public var keyDigit: Int {
        switch self {
        case .home:     return 1
        case .clients:  return 2
        case .pipeline: return 3
        case .settings: return 4
        }
    }

    /// English menu label. The xcstrings catalog handles FR via the
    /// usual `String(localized:)` lookup — this string is the lookup
    /// key under the `command.tab.<rawValue>` namespace.
    public var localizedKey: String {
        "command.tab.\(rawValue)"
    }

    /// Fallback English string used when the host bundle hasn't been
    /// loaded yet (unit tests on the pure type, no app bundle).
    public var fallbackTitle: String {
        switch self {
        case .home:     return "Home"
        case .clients:  return "Clients"
        case .pipeline: return "Pipeline"
        case .settings: return "Settings"
        }
    }

    /// Resolves a key-equivalent digit (1...4) back to the matching
    /// TabShortcut. Returns nil for anything outside that range.
    public static func from(keyDigit digit: Int) -> TabShortcut? {
        Self.allCases.first { $0.keyDigit == digit }
    }
}

/// SwiftUI `Commands` builder mounted on the main `WindowGroup`.
/// Surfaces every keyboard shortcut needed for Stage Manager / Mac
/// Catalyst flow in the menu bar at the top of the screen.
///
/// Every action posts a `Notification` on `NotificationCenter.default`
/// rather than mutating `@State` directly — `Commands` builders run
/// in a separate evaluation context from the scene's body, and we
/// want single owners (`RootView` for `selection`, `HomeView` for
/// `isAuditing`) of the matching `@State` properties.
struct StageManagerCommands: Commands {
    var body: some Commands {
        // ⌘N — New Audit, mounted in the standard "New" slot so the
        // system places it under File on Mac Catalyst.
        CommandGroup(replacing: .newItem) {
            Button {
                NotificationCenter.default.post(
                    name: .mindCommandNewAudit,
                    object: nil
                )
                MINDTelemetry.info("mac.shortcut.fired", data: ["key": "cmd-n"])
            } label: {
                Text("command.newAudit", bundle: .main)
            }
            .keyboardShortcut("n", modifiers: .command)

            // v1.0-alpha.12 — ⌘B opens the Bootstrap wizard from
            // anywhere. Sits in the .newItem group with ⌘N so both
            // "fresh start" actions cluster under File on Catalyst.
            Button {
                NotificationCenter.default.post(
                    name: .mindCommandBootstrap,
                    object: nil
                )
                MINDTelemetry.info("mac.shortcut.fired", data: ["key": "cmd-b"])
            } label: {
                Text("menu.shortcuts.bootstrap", bundle: .main)
            }
            .keyboardShortcut("b", modifiers: .command)

            // v1.0-alpha.12 — ⌘I opens the Invoice composer. Same
            // .newItem cluster: every "create" action is a single
            // ⌘<letter> away under File.
            Button {
                NotificationCenter.default.post(
                    name: .mindCommandNewInvoice,
                    object: nil
                )
                MINDTelemetry.info("mac.shortcut.fired", data: ["key": "cmd-i"])
            } label: {
                Text("menu.shortcuts.newInvoice", bundle: .main)
            }
            .keyboardShortcut("i", modifiers: .command)
        }

        // v1.0-alpha.12 — ⌘L (lead inbox) + ⌘R (refresh) folded into
        // the standard "tool" command group so they sit under Edit on
        // Catalyst — they're "look at / sync now" actions that mirror
        // the pull-to-refresh + the toolbar items, not "create new".
        CommandGroup(after: .pasteboard) {
            Divider()
            Button {
                NotificationCenter.default.post(
                    name: .mindCommandLeadInbox,
                    object: nil
                )
                MINDTelemetry.info("mac.shortcut.fired", data: ["key": "cmd-l"])
            } label: {
                Text("menu.shortcuts.leadInbox", bundle: .main)
            }
            .keyboardShortcut("l", modifiers: .command)

            Button {
                NotificationCenter.default.post(
                    name: .mindCommandRefresh,
                    object: nil
                )
                MINDTelemetry.info("mac.shortcut.fired", data: ["key": "cmd-r"])
            } label: {
                Text("menu.shortcuts.refresh", bundle: .main)
            }
            .keyboardShortcut("r", modifiers: .command)

            Button {
                NotificationCenter.default.post(
                    name: .mindCommandFocusSearch,
                    object: nil
                )
                MINDTelemetry.info("mac.shortcut.fired", data: ["key": "cmd-f"])
            } label: {
                Text("menu.shortcuts.focusSearch", bundle: .main)
            }
            .keyboardShortcut("f", modifiers: .command)
        }

        // ⌘1...⌘4 — sidebar destinations, surfaced as a custom
        // "View" menu so the shortcuts show up next to their labels
        // in the menu bar on iPad / Mac Catalyst with a connected
        // hardware keyboard.
        CommandMenu(Text("command.view.menu", bundle: .main)) {
            ForEach(TabShortcut.allCases, id: \.self) { shortcut in
                Button {
                    NotificationCenter.default.post(
                        name: .mindCommandSelectTab,
                        object: nil,
                        userInfo: ["tab": shortcut.rawValue]
                    )
                    MINDTelemetry.info("mac.shortcut.fired",
                                       data: ["key": "cmd-\(shortcut.keyDigit)"])
                } label: {
                    Text(LocalizedStringKey(shortcut.localizedKey), bundle: .main)
                }
                .keyboardShortcut(
                    KeyEquivalent(Character(String(shortcut.keyDigit))),
                    modifiers: .command
                )
            }

            Divider()

            // v1.0-alpha.12 — ⌘P jumps to Pipeline (mnemonic) and
            // ⌘, jumps to Settings (mac "preferences" convention).
            // Both reuse the existing select-tab notification so the
            // RootView listener stays single-source.
            Button {
                NotificationCenter.default.post(
                    name: .mindCommandSelectTab,
                    object: nil,
                    userInfo: ["tab": "pipeline"]
                )
                MINDTelemetry.info("mac.shortcut.fired", data: ["key": "cmd-p"])
            } label: {
                Text("menu.shortcuts.pipelineTab", bundle: .main)
            }
            .keyboardShortcut("p", modifiers: .command)

            Button {
                NotificationCenter.default.post(
                    name: .mindCommandSelectTab,
                    object: nil,
                    userInfo: ["tab": "settings"]
                )
                MINDTelemetry.info("mac.shortcut.fired", data: ["key": "cmd-comma"])
            } label: {
                Text("menu.shortcuts.settingsTab", bundle: .main)
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        // v1.0-alpha.12 — Project actions menu. The four ⌘⇧ shortcuts
        // mirror the buttons inside ProjectDetailSheet so a user with
        // a sheet open can fire them from the menu bar without
        // hunting for the in-sheet CTA.
        CommandMenu(Text("menu.project.menu", bundle: .main)) {
            Button {
                NotificationCenter.default.post(
                    name: .mindCommandAuditSource,
                    object: nil
                )
                MINDTelemetry.info("mac.shortcut.fired", data: ["key": "cmd-shift-a"])
            } label: {
                Text("menu.shortcuts.auditSource", bundle: .main)
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])

            Button {
                NotificationCenter.default.post(
                    name: .mindCommandBattleMode,
                    object: nil
                )
                MINDTelemetry.info("mac.shortcut.fired", data: ["key": "cmd-shift-b"])
            } label: {
                Text("menu.shortcuts.battleMode", bundle: .main)
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])

            Button {
                NotificationCenter.default.post(
                    name: .mindCommandOutreach,
                    object: nil
                )
                MINDTelemetry.info("mac.shortcut.fired", data: ["key": "cmd-shift-e"])
            } label: {
                Text("menu.shortcuts.outreach", bundle: .main)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Button {
                NotificationCenter.default.post(
                    name: .mindCommandDeploy,
                    object: nil
                )
                MINDTelemetry.info("mac.shortcut.fired", data: ["key": "cmd-shift-d"])
            } label: {
                Text("menu.shortcuts.deploy", bundle: .main)
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
        }
    }
}
