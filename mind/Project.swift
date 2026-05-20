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
        // v0.8 — Calendar (EventKit) integration. Both keys are required
        // on iOS 17+: the system prompts with the FullAccess string when
        // we call `requestFullAccessToEvents()`, and falls back to the
        // legacy key for write-only paths we may add later.
        "NSCalendarsFullAccessUsageDescription": "MIND lit ton agenda pour surfacer les rendez-vous du jour sur l'accueil et créer un nœud par réunion en un tap.",
        "NSCalendarsUsageDescription": "MIND lit ton agenda pour surfacer les rendez-vous du jour sur l'accueil et créer un nœud par réunion en un tap.",
        // v0.9 — HealthKit weekly insights. Apple requires BOTH read and
        // write usage strings even though we only read, otherwise the
        // App Store reviewer rejects the build. The FR copy explicitly
        // says "aucune donnée ne quitte ton appareil" so the user
        // knows the permission is local-only.
        "NSHealthShareUsageDescription": "MIND lit ton activité physique (pas, sommeil, minutes actives) sur 7 jours pour afficher un résumé hebdomadaire à côté de tes stats Focus. Aucune donnée ne quitte ton appareil.",
        "NSHealthUpdateUsageDescription": "MIND lit ton activité physique (pas, sommeil, minutes actives) sur 7 jours pour afficher un résumé hebdomadaire à côté de tes stats Focus. Aucune donnée ne quitte ton appareil.",
        // v0.10 — Reminders bidirectional sync. Both keys are required
        // on iOS 17+: the system prompts with the FullAccess string
        // when we call `requestFullAccessToReminders()`, the legacy
        // key remains as a fallback for any old framework code paths.
        "NSRemindersFullAccessUsageDescription": "MIND mirroite tes tâches avec l'app Rappels pour que tu puisses cocher une tâche depuis Siri, l'Apple Watch ou ton Mac et la voir disparaître ici aussi.",
        "NSRemindersUsageDescription": "MIND mirroite tes tâches avec l'app Rappels pour que tu puisses cocher une tâche depuis Siri, l'Apple Watch ou ton Mac et la voir disparaître ici aussi.",
        "UIBackgroundModes": ["audio", "processing", "fetch"],
        "BGTaskSchedulerPermittedIdentifiers": ["app.mind.ios.refresh"],
        "ITSAppUsesNonExemptEncryption": false,
        "NSSupportsLiveActivities": true,
        "NSSupportsLiveActivitiesFrequentUpdates": true,
        // v0.17 — Register the `mind://` URL scheme so iOS routes
        // `mind://brief` (fired from the daily morning brief
        // notification) into `RootView.onOpenURL`, which flips the
        // DailyBriefSheet on Home. Single scheme keeps the
        // deep-link surface minimal — future routes (`mind://focus`,
        // `mind://capture`) reuse the same scheme.
        "CFBundleURLTypes": [
            [
                "CFBundleURLName": "app.mind.ios.deeplink",
                "CFBundleURLSchemes": ["mind"],
            ],
        ],
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
        // v0.8 — CalendarEventTests cover the pure value type + Array
        // helpers used by the HomeView "Aujourd'hui" card.
        .target(name: Module.calendarKit.rawValue),
        // v0.9 — WeeklySummaryTests lock the pure value type used by
        // the HomeView "Cette semaine" health card. HealthReader itself
        // is exercised end-to-end via the simulator screenshot.
        .target(name: Module.healthInsights.rawValue),
        // v0.10 — RemindersSyncEngineTests exercise the pure diff
        // logic of the bidirectional Reminders sync — every action
        // (create node, create reminder, update either side, bind a
        // pre-existing pairing) is locked by a test. The EventKit-
        // backed `RemindersStore` is exercised end-to-end via the
        // simulator screenshot.
        .target(name: Module.remindersKit.rawValue),
        // v0.11 — NotionPageBuilderTests exercise the pure builder
        // that turns an `AuditReport` into the JSON dict POST
        // /v1/pages expects. The `NotionClient` actor itself is
        // exercised end-to-end via the Settings "Test sync" button
        // on a real device + the simulator screenshot.
        .target(name: Module.notionKit.rawValue),
        // v0.12 — LinearIssueBuilderTests + LinearTeamTests exercise
        // the pure issueInput(for:teamID:) builder used by the
        // AuditSheet "Push to Linear" buttons, and the LinearTeam
        // value type used by the Settings team picker. The
        // `LinearClient` actor is exercised end-to-end through the
        // simulator screenshot.
        .target(name: Module.linearKit.rawValue),
        // v0.19 — OCRServiceTests link Capture so we can lock the
        // pure `assemble(from:)` helper, the soft-fail contract on
        // empty input, the OCRResult Sendable + Equatable shape,
        // and the language-thread default. Vision itself runs in
        // the simulator at test time but most tests don't depend
        // on it — the assembly helper is the load-bearing path.
        .target(name: Module.capture.rawValue),
        // v0.21 — ClientPortalBuilderTests + PortalWriterTests lock
        // the pure HTML generator (slug, escaping, gauges, page-weight
        // ceiling) and the actor write helper. AuditKit is already
        // linked transitively via the target.
        .target(name: Module.clientPortalKit.rawValue),
        // v0.22 — LiveBroadcastWriterTests lock the JSON wire format,
        // the actor's atomic write contract, the token format, the
        // HTML template byte budget, and the determinism of the
        // canonical encoder. AuditKit is already linked transitively.
        .target(name: Module.liveBroadcastKit.rawValue),
        // v0.26 — OutreachKitTests lock the pure
        // `OutreachPromptBuilder` (prompt body anchors, voice tone
        // injection, audit grounding, deterministic output) and the
        // `OutreachMailto` URL escaping contract (subject + body +
        // recipient nil + accents + 5000+ char body). The
        // `OutreachEmailGenerator` actor's HTTP path is exercised
        // end-to-end via the simulator screenshot.
        .target(name: Module.outreachKit.rawValue),
        // v0.31 — InvoiceTests lock the pure `Invoice` value type
        // (Codable, VAT math, due-date defaults), the
        // `InvoiceStripeLinkBuilder.appendAmount(...)` URL builder
        // (query parameter escaping, amount rounding, base URL
        // validation), and the `InvoicePDFRenderer.render(...)` Data
        // contract (non-empty output, optional SIRET/IBAN graceful
        // skip). The `InvoiceStore` actor's sequential numbering
        // is also exercised — a hermetic temp directory keeps the
        // counter ratchet test from leaking onto disk between runs.
        .target(name: Module.invoiceKit.rawValue),
        // v0.22.1 — WatchCaptureKit tests lock the pure substrate
        // behind the deferred Watch surface — the `WatchCaptureRecord`
        // Codable round-trip, the `WatchCaptureTranscriptAssembler`
        // normalisation (whitespace collapse, control strip, longest-
        // fragment pick, sentence-cut title derivation), the
        // `WatchCaptureNodeBuilder` draft shape (kind / tags /
        // content clamp / empty-transcript skip), and the
        // `WatchCaptureQueue` actor's atomic enqueue + drain (sort
        // by startedAt, idempotent on id, remove on sync). The
        // future watchOS App + CloudKit mirror plug into the same
        // substrate without re-rolling the data shape.
        .target(name: Module.watchCaptureKit.rawValue),
        // v0.25.1 — VisionSpatialKit tests lock the pure substrate
        // behind the deferred Vision Pro layout — the `SpatialAnchor`
        // bounds clamping + Codable round-trip, the
        // `SpatialPanel` size clamping + title trimming, the
        // `SpatialLayoutBuilder` deterministic preset math (bento
        // grid columns + cinema arc + atelier sphere), and the
        // `SpatialLayoutStore` actor's hermetic JSON persistence
        // round-trip. The future visionOS App + RealityView surface
        // plug into the same substrate without re-rolling the
        // anchor / panel shape.
        .target(name: Module.visionSpatialKit.rawValue),
        // v1.0-alpha.7 — SwarmKit tests cover the pure
        // `SEOSwarmPromptBuilder` (system + page prompt anchors,
        // deterministic shape, JSON-only contract, population
        // gracing), the `SwarmZoneCatalog` static reference data
        // (>=200 zones, URL-safe slugs, no duplicates), the
        // `SEOSwarmExporter` directory-tree shape (one file per
        // page, path uses forward slashes, content includes
        // JSON-LD + markdown), and the `SEOSwarmStore` actor's
        // hermetic JSON persistence in a temp directory.
        .target(name: Module.swarmKit.rawValue),
        // v1.0-alpha.8 — ProjectHealthKit tests cover the pure
        // value types (`VercelDeployment` / `GitHubCommit` /
        // `LighthouseScore` Codable round-trips), the static URL
        // builders (`VercelClient.deploymentsURL`, the GitHub repo /
        // commits / issues endpoints, `LighthouseProbe.endpoint`),
        // the on-disk cache (`ProjectHealthCache` TTL / partial
        // update / clear-all contract), and the two Keychain stores
        // (`VercelTokenStore` + `GitHubTokenStore`) under a skip-on-
        // Simulator guard since the SImulator keychain is flaky.
        .target(name: Module.projectHealthKit.rawValue),
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
                // Accept any share that includes a URL, plain text, or
                // a vCard (Contacts.app "Add to MIND"). Quantities are
                // capped at 1 — multi-select is a future iteration.
                // v0.13 — adding `NSExtensionActivationSupportsVCardWithMaxCount`
                // is what surfaces MIND on the Contacts.app share sheet
                // (long-press a contact → "Add to MIND").
                "NSExtensionActivationRule": [
                    "NSExtensionActivationSupportsWebURLWithMaxCount": 1,
                    "NSExtensionActivationSupportsText": true,
                    "NSExtensionActivationSupportsVCardWithMaxCount": 1,
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
