import ProjectDescription

public enum Module: String, CaseIterable {
    case designSystem = "DesignSystem"
    case graphCore = "GraphCore"
    case notes = "Notes"
    case intelligence = "Intelligence"
    case settings = "Settings"
    case chat = "Chat"
    case capture = "Capture"
    case mindIntents = "MINDIntents"
    case focusKit = "FocusKit"
    case visualKit = "VisualKit"
    case auditKit = "AuditKit"
    case calendarKit = "CalendarKit"
    case healthInsights = "HealthInsights"
    case remindersKit = "RemindersKit"
    case notionKit = "NotionKit"
    case linearKit = "LinearKit"
    case clientPortalKit = "ClientPortalKit"

    public var bundleId: String {
        "app.mind.ios.\(rawValue.lowercased())"
    }

    public var path: Path {
        .relativeToRoot("Modules/\(rawValue)")
    }

    public var dependencies: [TargetDependency] {
        switch self {
        case .designSystem:
            return []
        case .graphCore:
            return []
        case .notes:
            return [
                .target(name: Module.graphCore.rawValue),
                .target(name: Module.designSystem.rawValue),
            ]
        case .intelligence:
            return [
                .target(name: Module.graphCore.rawValue),
            ]
        case .settings:
            return [
                .target(name: Module.designSystem.rawValue),
                .target(name: Module.intelligence.rawValue),
                .target(name: Module.visualKit.rawValue),
                // Needed so Settings → Danger Zone can reach
                // GraphCore.sharedContainer for the "Wipe all data"
                // action and SpotlightIndexer for "Reset Spotlight".
                .target(name: Module.graphCore.rawValue),
                // v0.9 — Settings owns the HealthInsights opt-in toggle
                // and calls HealthReader.requestAccess() when the user
                // enables it. Depending on HealthInsights here means we
                // never reach across module boundaries from RootView to
                // trigger the authorization sheet.
                .target(name: Module.healthInsights.rawValue),
                // v0.10 — Settings owns the Reminders sync opt-in toggle
                // and calls RemindersStore.requestAccess() on toggle-on
                // so the EventKit permission sheet appears as a direct
                // consequence of the user's tap.
                .target(name: Module.remindersKit.rawValue),
                // v0.11 — Settings owns the Notion sync section (paste
                // integration token, paste database ID, "Test sync"
                // button). Depending on NotionKit here means the token
                // save + validate flow stays inside the same view that
                // shows its green/red dot status.
                .target(name: Module.notionKit.rawValue),
                // v0.12 — Settings owns the Linear sync section (paste
                // personal API key, save+validate button with green/red
                // dot, team picker once the token validates). Same
                // co-location rationale as NotionKit.
                .target(name: Module.linearKit.rawValue),
            ]
        case .chat:
            return [
                .target(name: Module.designSystem.rawValue),
                .target(name: Module.graphCore.rawValue),
                .target(name: Module.intelligence.rawValue),
            ]
        case .capture:
            return [
                .target(name: Module.designSystem.rawValue),
                .target(name: Module.graphCore.rawValue),
                .target(name: Module.intelligence.rawValue),
            ]
        case .mindIntents:
            return [
                .target(name: Module.graphCore.rawValue),
                .target(name: Module.intelligence.rawValue),
                .target(name: Module.auditKit.rawValue),
            ]
        case .focusKit:
            return [
                .target(name: Module.graphCore.rawValue),
            ]
        case .visualKit:
            return [
                .target(name: Module.graphCore.rawValue),
                .target(name: Module.intelligence.rawValue),
                .target(name: Module.auditKit.rawValue),
            ]
        case .auditKit:
            return [
                .target(name: Module.graphCore.rawValue),
                .target(name: Module.intelligence.rawValue),
            ]
        case .calendarKit:
            // EventKit reader + lightweight CalendarEvent value type used
            // by the HomeView "Aujourd'hui" card. Depends on GraphCore so
            // the card can mint a .meeting Node from a tap, and on
            // DesignSystem so any future in-module UI can reuse Liquid
            // Glass tokens without reaching across the layering boundary.
            return [
                .target(name: Module.graphCore.rawValue),
                .target(name: Module.designSystem.rawValue),
            ]
        case .healthInsights:
            // HealthKit reader + pure WeeklySummary value type for the
            // HomeView "Cette semaine" card (v0.9). Depends on GraphCore
            // so a future tap → Node flow stays consistent with
            // CalendarKit, and on DesignSystem for the same layering
            // reason. The HealthKit framework itself is linked from the
            // module's source via `import HealthKit`, gated behind
            // `#if canImport(HealthKit)` so the module still compiles
            // on platforms without it.
            return [
                .target(name: Module.graphCore.rawValue),
                .target(name: Module.designSystem.rawValue),
            ]
        case .remindersKit:
            // v0.10 — Reminders bidirectional sync. Depends on GraphCore
            // because the sync engine projects task-shaped Nodes into
            // `NodeProjection` value types before diffing them against
            // the EventKit snapshots, and writes back the paired
            // `reminderExternalID`. EventKit is linked from the module
            // source via `import EventKit` (same model as CalendarKit's
            // EKEventStore usage).
            return [
                .target(name: Module.graphCore.rawValue),
            ]
        case .notionKit:
            // v0.11 — One-way MIND → Notion sync. Depends on GraphCore
            // for MINDTelemetry breadcrumbs (notion.token.saved /
            // notion.page.created / …) and on AuditKit for the
            // `AuditReport` value type the NotionPageBuilder consumes.
            // No DesignSystem dep — NotionKit is pure model + actor
            // client; the visible UI lives in Settings / App which
            // already link DesignSystem.
            return [
                .target(name: Module.graphCore.rawValue),
                .target(name: Module.auditKit.rawValue),
            ]
        case .linearKit:
            // v0.12 — Audit Quick Wins → Linear issues. Same dep shape
            // as NotionKit: GraphCore for MINDTelemetry breadcrumbs
            // (linear.token.saved / linear.issue.created / …) and
            // AuditKit for `AuditReport.QuickWin`, which the pure
            // `LinearIssueBuilder` consumes. The actor `LinearClient`
            // posts to https://api.linear.app/graphql; the UI lives in
            // Settings + AuditSheet which already link DesignSystem.
            return [
                .target(name: Module.graphCore.rawValue),
                .target(name: Module.auditKit.rawValue),
            ]
        case .clientPortalKit:
            // v0.21 — MIND Client Portal Generator. Turns any completed
            // `AuditReport` into a self-contained premium HTML static
            // site. Depends on AuditKit for the `AuditReport` value
            // type and on GraphCore for `MINDTelemetry` breadcrumbs
            // (clientPortal.generated / clientPortal.shared / …). No
            // DesignSystem dep — the output is HTML, not SwiftUI, and
            // every visual decision lives in the Liquid Glass HTML
            // template strings inline (gradients, backdrop-filter,
            // typography). The host App target invokes
            // `ClientPortalBuilder.generateSite(for:brand:)` to obtain
            // an in-memory `ClientPortalArchive`, then hands it to the
            // `PortalWriter` actor which writes every file to
            // `Documents/client-portals/<slug>-<date>/`.
            return [
                .target(name: Module.graphCore.rawValue),
                .target(name: Module.auditKit.rawValue),
            ]
        }
    }

    public func target() -> Target {
        .target(
            name: rawValue,
            destinations: .iOS,
            product: .framework,
            bundleId: bundleId,
            deploymentTargets: .iOS("26.0"),
            sources: ["Modules/\(rawValue)/Sources/**"],
            dependencies: dependencies,
            settings: .settings(base: [
                "SWIFT_VERSION": "6.0",
            ])
        )
    }
}
