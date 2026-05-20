import Foundation
import SwiftUI

// v1.0-alpha.12 — Mac Catalyst polish substrate.
//
// MIND has been iPhone-first. With the Cockpit Studio scope, Mehdi
// will want to operate it on his Mac (Magic Keyboard + 27" Numelite
// workstation). This file ships the pure substrate that the menu bar,
// the Catalyst toolbar, the Touch Bar, the dock badge updater, and the
// SwiftUI scene-restoration layer all read from — keeping the data
// shape and the @MainActor SwiftUI surface decoupled so every piece
// is unit-testable without dragging in the host bundle or a window.
//
// Three concerns live here:
//
//   1. `MacToolbarAction` — table of every action surfaced through the
//      Catalyst toolbar / iPad menu bar / Touch Bar. Each row carries
//      a stable raw value (used as the `Notification.Name`), a
//      localized title key, an SF Symbol name, and a key-equivalent
//      hint. The SwiftUI `.toolbar` modifier reads from this table.
//
//   2. `MacShortcut` — every keyboard shortcut beyond the ⌘N / ⌘1-⌘4
//      pair shipped in v0.24.1. Adds ⌘B / ⌘L / ⌘I / ⌘R / ⌘P / ⌘, plus
//      the ⌘-shift modifiers for the project-detail actions. The pure
//      mapping table is what the `Commands` SwiftUI builder reads.
//
//   3. `MacSceneStorageKey` — namespaced string constants for every
//      `@SceneStorage` key MIND uses on Mac Catalyst (selected tab,
//      selected project ID, selected lead ID, sidebar visibility).
//      Locking the namespace means a future @SceneStorage key
//      collision with another part of the codebase becomes a build-
//      visible regression.

// MARK: - MacToolbarAction

/// Every action the Mac Catalyst toolbar surfaces. Each case is pure
/// data: rawValue doubles as the `Notification.Name` posted on tap,
/// `localizedKey` is the xcstrings catalog lookup, and `systemImage`
/// is the SF Symbol the toolbar item renders.
public enum MacToolbarAction: String, CaseIterable, Sendable {
    /// Surface the Lead inbox — flips selection to Home and posts
    /// `.mindCommandLeadInbox` so HomeView scrolls to the inbox card.
    case leads = "app.mind.ios.command.leadInbox"

    /// Opens the audit sheet. Same payload as ⌘N — kept distinct from
    /// the `newAudit` enum so the toolbar / Touch Bar can render its
    /// own glyph and label.
    case audit = "app.mind.ios.command.audit"

    /// Opens the Bootstrap wizard sheet (new project scaffolder).
    case bootstrap = "app.mind.ios.command.bootstrap"

    /// Triggers a portfolio-health refresh fan-out. HomeView listens
    /// for it and runs the same pull-to-refresh path the user reaches
    /// via the swipe-down gesture on iPhone.
    case refresh = "app.mind.ios.command.refresh"

    /// xcstrings catalog key (FR/EN) for the action's user-visible
    /// title. The catalog mirrors `toolbar.<rawCaseName>`.
    public var localizedKey: String {
        switch self {
        case .leads:     return "toolbar.leads"
        case .audit:     return "toolbar.audit"
        case .bootstrap: return "toolbar.bootstrap"
        case .refresh:   return "toolbar.refresh"
        }
    }

    /// English fallback string used when the host bundle isn't loaded
    /// (e.g. inside a unit-test process that doesn't link the .lproj).
    public var fallbackTitle: String {
        switch self {
        case .leads:     return "Leads"
        case .audit:     return "Audit"
        case .bootstrap: return "Bootstrap"
        case .refresh:   return "Refresh"
        }
    }

    /// SF Symbol name rendered by the toolbar item / Touch Bar.
    public var systemImage: String {
        switch self {
        case .leads:     return "tray.full.fill"
        case .audit:     return "magnifyingglass"
        case .bootstrap: return "sparkles.rectangle.stack.fill"
        case .refresh:   return "arrow.clockwise"
        }
    }

    /// Posts the matching notification on the default center. Single
    /// helper here so the toolbar item, Touch Bar item, and the menu
    /// bar entry all go through the same path — tests can post
    /// directly to assert downstream listeners (HomeView, RootView)
    /// react correctly without owning a window.
    public var notificationName: Notification.Name {
        Notification.Name(rawValue)
    }
}

extension Notification.Name {
    /// ⌘L — surface the lead inbox card on Home.
    static let mindCommandLeadInbox = MacToolbarAction.leads.notificationName

    /// Toolbar-only audit entry. Kept distinct from
    /// `mindCommandNewAudit` so the toolbar surface and the ⌘N menu
    /// entry can fire independently without one stealing the other's
    /// breadcrumbs in MINDTelemetry.
    static let mindCommandAuditToolbar = MacToolbarAction.audit.notificationName

    /// ⌘B — open Bootstrap wizard from anywhere.
    static let mindCommandBootstrap = MacToolbarAction.bootstrap.notificationName

    /// ⌘R — refresh portfolio health. HomeView listens for it.
    static let mindCommandRefresh = MacToolbarAction.refresh.notificationName

    /// ⌘I — open the Invoice sheet on the current project (or the
    /// generic invoice composer if no project is active).
    static let mindCommandNewInvoice = Notification.Name("app.mind.ios.command.newInvoice")

    /// ⌘F — focus the search field in the current view.
    static let mindCommandFocusSearch = Notification.Name("app.mind.ios.command.focusSearch")

    /// ⌘⇧A — audit source code of current project (Repository-aware
    /// Audit). Triggered from the menu when a ProjectDetail is open.
    static let mindCommandAuditSource = Notification.Name("app.mind.ios.command.auditSource")

    /// ⌘⇧B — Battle Mode.
    static let mindCommandBattleMode = Notification.Name("app.mind.ios.command.battleMode")

    /// ⌘⇧E — OutreachSheet (Reply assistant).
    static let mindCommandOutreach = Notification.Name("app.mind.ios.command.outreach")

    /// ⌘⇧D — Vercel redeploy current project.
    static let mindCommandDeploy = Notification.Name("app.mind.ios.command.deploy")
}

// MARK: - MacShortcut

/// Catalog of every keyboard shortcut MIND ships beyond the v0.24.1
/// ⌘N + ⌘1-⌘4 pair. Each row carries the key, the modifier set, the
/// notification name fired, and a localized menu label key. The
/// `Commands` SwiftUI builder reads this table to render the menu
/// entries — adding a new shortcut means appending a case here,
/// nothing else.
public enum MacShortcut: String, CaseIterable, Sendable {
    /// ⌘B — Bootstrap wizard.
    case bootstrap
    /// ⌘L — Lead inbox.
    case leadInbox
    /// ⌘I — New Invoice.
    case newInvoice
    /// ⌘R — Refresh portfolio.
    case refresh
    /// ⌘P — Pipeline tab.
    case pipelineTab
    /// ⌘, — Settings tab (standard "preferences" mac convention).
    case settingsTab
    /// ⌘F — Focus search field.
    case focusSearch
    /// ⌘⇧A — Audit source code of current project.
    case auditSource
    /// ⌘⇧B — Battle Mode.
    case battleMode
    /// ⌘⇧E — Outreach (Reply assistant).
    case outreach
    /// ⌘⇧D — Deploy current project (Vercel redeploy).
    case deploy

    /// The key character used in `keyboardShortcut(...)`.
    public var key: Character {
        switch self {
        case .bootstrap:   return "b"
        case .leadInbox:   return "l"
        case .newInvoice:  return "i"
        case .refresh:     return "r"
        case .pipelineTab: return "p"
        case .settingsTab: return ","
        case .focusSearch: return "f"
        case .auditSource: return "a"
        case .battleMode:  return "b"
        case .outreach:    return "e"
        case .deploy:      return "d"
        }
    }

    /// Modifier set the shortcut requires. SwiftUI's `EventModifiers`
    /// is the runtime side; we model it here as a Sendable struct so
    /// the table stays pure for unit tests (EventModifiers itself is
    /// MainActor-bound).
    public struct Modifiers: Hashable, Sendable {
        public let command: Bool
        public let shift: Bool

        public init(command: Bool = true, shift: Bool = false) {
            self.command = command
            self.shift = shift
        }
    }

    /// Modifiers for the shortcut. ⌘ for everything; ⌘⇧ for the
    /// project-action quartet.
    public var modifiers: Modifiers {
        switch self {
        case .bootstrap, .leadInbox, .newInvoice, .refresh,
             .pipelineTab, .settingsTab, .focusSearch:
            return Modifiers(command: true, shift: false)
        case .auditSource, .battleMode, .outreach, .deploy:
            return Modifiers(command: true, shift: true)
        }
    }

    /// The `Notification.Name` the shortcut posts on. Each shortcut
    /// owns a uniquely-namespaced channel — no two shortcuts collide,
    /// locked by `test_shortcutNotifications_areUnique`.
    public var notificationName: Notification.Name {
        switch self {
        case .bootstrap:   return .mindCommandBootstrap
        case .leadInbox:   return .mindCommandLeadInbox
        case .newInvoice:  return .mindCommandNewInvoice
        case .refresh:     return .mindCommandRefresh
        case .pipelineTab: return .mindCommandSelectTab
        case .settingsTab: return .mindCommandSelectTab
        case .focusSearch: return .mindCommandFocusSearch
        case .auditSource: return .mindCommandAuditSource
        case .battleMode:  return .mindCommandBattleMode
        case .outreach:    return .mindCommandOutreach
        case .deploy:      return .mindCommandDeploy
        }
    }

    /// xcstrings catalog key. Single namespace under
    /// `menu.shortcuts.<rawValue>` so the test sweep over xcstrings
    /// catches a missing translation per case.
    public var localizedKey: String {
        "menu.shortcuts.\(rawValue)"
    }

    /// English fallback. Tests run outside the host bundle.
    public var fallbackTitle: String {
        switch self {
        case .bootstrap:   return "Bootstrap"
        case .leadInbox:   return "Lead Inbox"
        case .newInvoice:  return "New Invoice"
        case .refresh:     return "Refresh"
        case .pipelineTab: return "Pipeline"
        case .settingsTab: return "Settings"
        case .focusSearch: return "Search"
        case .auditSource: return "Audit Source Code"
        case .battleMode:  return "Battle Mode"
        case .outreach:    return "Reply Assistant"
        case .deploy:      return "Redeploy"
        }
    }

    /// The `userInfo` payload posted alongside the notification when
    /// the shortcut fires. Most shortcuts have no payload; the two
    /// tab-switch entries carry the destination tab's rawValue so
    /// `RootView.onReceive(.mindCommandSelectTab)` can decode it.
    public var notificationUserInfo: [String: String] {
        switch self {
        case .pipelineTab: return ["tab": "pipeline"]
        case .settingsTab: return ["tab": "settings"]
        default:           return [:]
        }
    }
}

// MARK: - MacSceneStorageKey

/// Namespaced string constants for every `@SceneStorage` key MIND
/// uses on Mac Catalyst (and iPad multitasking). Centralising them
/// keeps the namespace audit-able from a single test and prevents
/// silent collisions with `@AppStorage` keys elsewhere in the codebase.
public enum MacSceneStorageKey {
    /// The selected MINDTab. Persisted across window restores so
    /// closing MIND on the Pipeline tab and reopening lands back on
    /// Pipeline, not Home.
    public static let selectedTab = "mind.scene.selectedTab"

    /// UUID string of the currently-open ProjectDetail sheet, if any.
    /// Empty string when no detail is presented.
    public static let selectedProjectID = "mind.scene.selectedProjectID"

    /// UUID string of the currently-open LeadDetail sheet, if any.
    /// Empty string when no detail is presented.
    public static let selectedLeadID = "mind.scene.selectedLeadID"

    /// NavigationSplitView sidebar visibility on regular-width layouts.
    /// Persisted as a raw string ("all" / "doubleColumn" /
    /// "detailOnly") rather than the enum because @SceneStorage
    /// requires RawRepresentable conformance the OS handles cleanly
    /// for primitive types.
    public static let sidebarVisibility = "mind.scene.sidebarVisibility"

    /// Every key the SceneStorage layer uses. Locked by
    /// `test_allKeys_followNamespace` so a future addition can't drift
    /// out of the `mind.scene.*` namespace.
    public static let allKeys: [String] = [
        selectedTab,
        selectedProjectID,
        selectedLeadID,
        sidebarVisibility
    ]
}

// MARK: - Dock badge

/// v1.0-alpha.12 — Catalyst-only helper that pushes the count of new
/// leads onto the dock icon. iPhone / iPad simply no-op (the OS
/// already surfaces the badge through the home-screen icon path).
///
/// The `count` API is intentionally pure-data: the production call
/// path lives behind `#if targetEnvironment(macCatalyst)` in
/// `MINDApp.refreshDockBadge(...)` so SwiftUI previews / unit tests
/// on iOS Simulator don't try to set a non-existent dock badge.
public enum MacDockBadge {
    /// Returns the count value the badge should display for a given
    /// new-lead count. Clamps to 0 (no negative badges) and caps at
    /// 99 so a webhook flood doesn't render "1247" on the dock.
    public static func displayCount(forNewLeads count: Int) -> Int {
        max(0, min(99, count))
    }

    /// The accessibility label string-format key used by the
    /// xcstrings catalog. `mac.dockBadge.leads.format` carries a
    /// `%d` placeholder for the count.
    public static let accessibilityKey = "mac.dockBadge.leads.format"
}
