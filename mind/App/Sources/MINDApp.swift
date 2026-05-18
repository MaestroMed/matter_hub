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

    init() {
        bootstrapSentry()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.light)
        }
        .modelContainer(GraphCore.sharedContainer)
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
    }
}
