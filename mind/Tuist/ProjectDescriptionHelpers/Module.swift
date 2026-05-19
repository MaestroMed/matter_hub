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
