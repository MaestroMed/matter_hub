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
    case auditKit = "AuditKit"

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
            return []
        case .auditKit:
            return [
                .target(name: Module.graphCore.rawValue),
                .target(name: Module.intelligence.rawValue),
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
