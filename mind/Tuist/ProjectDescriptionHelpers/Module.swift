import ProjectDescription

public enum Module: String, CaseIterable {
    case designSystem = "DesignSystem"
    case graphCore = "GraphCore"

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
        }
    }

    public func target() -> Target {
        .target(
            name: rawValue,
            destinations: .iOS,
            product: .framework,
            bundleId: bundleId,
            deploymentTargets: .iOS("18.0"),
            sources: ["Modules/\(rawValue)/Sources/**"],
            dependencies: dependencies,
            settings: .settings(base: [
                "SWIFT_VERSION": "6.0",
            ])
        )
    }
}
