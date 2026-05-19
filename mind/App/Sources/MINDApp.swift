import SwiftUI
import SwiftData
import AppIntents
import DesignSystem
import GraphCore
import MINDIntents
import Sentry
import Settings

@main
struct MINDApp: App {
    // Forces MINDAppShortcuts (and therefore CaptureIntent / AskMindIntent)
    // to be linked into the main binary so the App Intents metadata
    // processor can extract them and iOS can surface them in Siri,
    // Spotlight, Shortcuts and the Action Button.
    static let shortcutsProvider = MINDAppShortcuts.self

    @Environment(\.scenePhase) private var scenePhase

    init() {
        bootstrapSentry()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.light)
        }
        .modelContainer(GraphCore.sharedContainer)
        .onChange(of: scenePhase) { _, newPhase in
            // When MIND comes back from background, persist any pending
            // SwiftData transactions immediately so CloudKit picks them
            // up on the next mirror cycle, and emit a breadcrumb so we
            // can correlate "user returned to app" with any sync events
            // in the Sentry timeline.
            switch newPhase {
            case .active:
                MINDTelemetry.info("lifecycle.foreground")
                refreshGraphFromCloud()
            case .background:
                MINDTelemetry.info("lifecycle.background")
            case .inactive:
                break
            @unknown default:
                break
            }
        }
    }

    /// Nudges SwiftData / NSPersistentCloudKitContainer to look for new
    /// remote changes by saving any pending writes on the main context.
    /// Save-with-no-changes is a no-op so this is cheap even when the
    /// graph hasn't been touched since the last foreground.
    @MainActor
    private func refreshGraphFromCloud() {
        let context = GraphCore.sharedContainer.mainContext
        if context.hasChanges {
            do {
                try context.save()
                MINDTelemetry.info("graph.foreground.save")
            } catch {
                MINDTelemetry.error(
                    "graph.foreground.save.failed",
                    data: ["error": String(describing: error)]
                )
            }
        }
    }

    /// Starts Sentry if the user has saved a DSN in Settings. Silently
    /// no-ops otherwise — Sentry is opt-in, no telemetry is sent until
    /// Mehdi explicitly turns it on.
    private func bootstrapSentry() {
        guard let dsn = MINDPreferences.currentSentryDSN(), !dsn.isEmpty else {
            return
        }
        SentrySDK.start { options in
            options.dsn = dsn
            options.debug = false
            options.tracesSampleRate = 0.2          // 20% performance traces
            options.profilesSampleRate = 0.2
            options.attachStacktrace = true
            options.attachScreenshot = false        // don't leak user content
            options.attachViewHierarchy = false     // same
            options.swiftAsyncStacktraces = true
            options.enableAutoPerformanceTracing = true
            options.enableNetworkBreadcrumbs = true
            // App-side identifier so Sentry's UI shows the right env.
            options.environment = "production"
            options.releaseName = "MIND@0.1.0"
        }

        // Plug MINDTelemetry into Sentry now that the SDK is up. Any
        // module calling `MINDTelemetry.breadcrumb(...)` flows through
        // this closure → SentrySDK.addBreadcrumb. Until this line runs,
        // calls are silent no-ops (tests, unsigned dev loop).
        Task { @MainActor in
            MINDTelemetry.sink = { event in
                let crumb = Breadcrumb()
                crumb.message = event.name
                crumb.category = event.category
                crumb.level = sentryLevel(for: event.level)
                crumb.timestamp = event.timestamp
                if !event.data.isEmpty {
                    crumb.data = event.data
                }
                SentrySDK.addBreadcrumb(crumb)
            }
            MINDTelemetry.breadcrumb(
                "App launched",
                category: "lifecycle",
                data: ["release": "MIND@0.1.0"]
            )
        }
    }
}

/// Tiny translator between MINDTelemetry levels and Sentry levels.
/// Kept free-standing so MINDTelemetry doesn't have to know Sentry
/// types — host-app concern only.
private func sentryLevel(for level: MINDTelemetry.Level) -> SentryLevel {
    switch level {
    case .debug:    return .debug
    case .info:     return .info
    case .warning:  return .warning
    case .error:    return .error
    case .critical: return .fatal
    }
}
