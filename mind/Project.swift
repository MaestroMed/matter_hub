import ProjectDescription
import ProjectDescriptionHelpers

let appBundleId = "app.mind.ios"
let appName = "MIND"

let appTarget: Target = .target(
    name: appName,
    destinations: .iOS,
    product: .app,
    bundleId: appBundleId,
    deploymentTargets: .iOS("26.0"),
    infoPlist: .extendingDefault(with: [
        "UILaunchScreen": ["UIColorName": "LaunchBackground"],
        "CFBundleDisplayName": "MIND",
        "CFBundleShortVersionString": "0.1.0",
        "CFBundleVersion": "1",
        "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait"],
        "NSMicrophoneUsageDescription": "MIND uses your microphone to capture voice notes and transcribe them on-device.",
        "NSSpeechRecognitionUsageDescription": "MIND transcribes your voice locally so you can capture thoughts hands-free.",
        "NSCameraUsageDescription": "MIND scans documents and images so they become part of your second brain.",
        "NSPhotoLibraryUsageDescription": "MIND can pull photos to enrich your knowledge graph.",
        "UIBackgroundModes": ["audio", "processing"],
        "ITSAppUsesNonExemptEncryption": false,
        "NSSupportsLiveActivities": true,
        "NSSupportsLiveActivitiesFrequentUpdates": true,
    ]),
    sources: ["App/Sources/**"],
    resources: ["App/Resources/**"],
    entitlements: .file(path: "App/MIND.entitlements"),
    dependencies: Module.allCases.map { .target(name: $0.rawValue) } + [
        .target(name: "MINDWidgets"),
        .external(name: "Sentry"),
    ],
    settings: .settings(base: [
        "SWIFT_VERSION": "6.0",
        "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    ])
)

let testTarget: Target = .target(
    name: "MINDTests",
    destinations: .iOS,
    product: .unitTests,
    bundleId: "\(appBundleId).tests",
    deploymentTargets: .iOS("26.0"),
    sources: ["Tests/Sources/**"],
    dependencies: [
        .target(name: appName),
        .target(name: Module.auditKit.rawValue),
        .target(name: Module.graphCore.rawValue),
        .target(name: Module.visualKit.rawValue),
        .target(name: Module.intelligence.rawValue),
    ],
    settings: .settings(base: [
        "SWIFT_VERSION": "6.0",
    ])
)

let widgetTarget: Target = .target(
    name: "MINDWidgets",
    destinations: .iOS,
    product: .appExtension,
    bundleId: "\(appBundleId).widgets",
    deploymentTargets: .iOS("26.0"),
    infoPlist: .extendingDefault(with: [
        "CFBundleDisplayName": "MIND Widgets",
        // Must match the parent app's version to satisfy
        // embeddedBinaryValidationUtility — Xcode flags a mismatch
        // when CFBundleShortVersionString differs from the host app.
        "CFBundleShortVersionString": "0.1.0",
        "CFBundleVersion": "1",
        "NSExtension": [
            "NSExtensionPointIdentifier": "com.apple.widgetkit-extension",
        ],
    ]),
    sources: ["Widgets/Sources/**"],
    resources: ["Widgets/Resources/**"],
    entitlements: .file(path: "Widgets/MINDWidgets.entitlements"),
    dependencies: [
        .target(name: Module.graphCore.rawValue),
        .target(name: Module.focusKit.rawValue),
    ],
    settings: .settings(base: [
        "SWIFT_VERSION": "6.0",
    ])
)

let project = Project(
    name: appName,
    organizationName: "MIND",
    options: .options(
        defaultKnownRegions: ["en", "fr"],
        developmentRegion: "en"
    ),
    settings: .settings(
        base: [
            "SWIFT_VERSION": "6.0",
            "IPHONEOS_DEPLOYMENT_TARGET": "26.0",
        ],
        configurations: [
            .debug(name: "Debug"),
            .release(name: "Release"),
        ]
    ),
    targets: [appTarget, widgetTarget, testTarget] + Module.allCases.map { $0.target() }
)
