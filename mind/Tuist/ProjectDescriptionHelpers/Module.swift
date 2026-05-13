import ProjectDescription

public enum Module: String, CaseIterable {
    case designSystem = "DesignSystem"
    case graphCore = "GraphCore"
    case intelligence = "Intelligence"
    case capture = "Capture"
    case notes = "Notes"

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
        case .intelligence:
            return [.target(name: Module.graphCore.rawValue)]
        case .capture:
            return [
                .target(name: Module.graphCore.rawValue),
                .target(name: Module.intelligence.rawValue),
                .target(name: Module.designSystem.rawValue),
            ]
        case .notes:
            return [
                .target(name: Module.graphCore.rawValue),
                .target(name: Module.intelligence.rawValue),
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
