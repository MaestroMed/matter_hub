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
        "UIBackgroundModes": ["audio", "processing", "fetch"],
        "BGTaskSchedulerPermittedIdentifiers": ["app.mind.ios.refresh"],
        "ITSAppUsesNonExemptEncryption": false,
        "NSSupportsLiveActivities": true,
        "NSSupportsLiveActivitiesFrequentUpdates": true,
    ]),
    sources: ["App/Sources/**"],
    resources: ["App/Resources/**"],
    entitlements: .file(path: "App/MIND.entitlements"),
    dependencies: Module.allCases.map { .target(name: $0.rawValue) } + [
        .target(name: "MINDWidgets"),
        .target(name: "MINDShareExtension"),
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
        .target(name: Module.settings.rawValue),
        // v0.5 — MarkdownRenderingTests link DesignSystem to verify the
        // pure markdown → AttributedString helper used by the Note editor.
        .target(name: Module.designSystem.rawValue),
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

// Share Extension — surfaces MIND in every share sheet (Safari, Mail,
// Notes, Messages, Photos) so the user can capture a URL or text
// payload in two taps. The extension is intentionally minimal: it
// serialises the share into the cross-process `ShareInbox` queue and
// hands control back to iOS. The host MIND app drains the queue on
// next foreground and turns each payload into a Node (auto-creating
// a `client` Node when the URL matches a known SaaS host).
let shareExtensionTarget: Target = .target(
    name: "MINDShareExtension",
    destinations: .iOS,
    product: .appExtension,
    bundleId: "\(appBundleId).shareextension",
    deploymentTargets: .iOS("26.0"),
    infoPlist: .extendingDefault(with: [
        "CFBundleDisplayName": "MIND",
        "CFBundleShortVersionString": "0.1.0",
        "CFBundleVersion": "1",
        "NSExtension": [
            "NSExtensionPointIdentifier": "com.apple.share-services",
            "NSExtensionPrincipalClass": "$(PRODUCT_MODULE_NAME).ShareViewController",
            "NSExtensionAttributes": [
                // Accept any share that includes either a URL or plain
                // text. Quantities are capped at 1 — multi-select is a
                // future iteration.
                "NSExtensionActivationRule": [
                    "NSExtensionActivationSupportsWebURLWithMaxCount": 1,
                    "NSExtensionActivationSupportsText": true,
                ],
            ],
        ],
    ]),
    sources: ["ShareExtension/Sources/**"],
    entitlements: .file(path: "ShareExtension/MINDShareExtension.entitlements"),
    dependencies: [
        .target(name: Module.graphCore.rawValue),
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
    targets: [appTarget, widgetTarget, shareExtensionTarget, testTarget] + Module.allCases.map { $0.target() }
)
