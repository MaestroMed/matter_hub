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
        bootstrapBackgroundRefresh()
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
                drainShareInbox()
            case .background:
                MINDTelemetry.info("lifecycle.background")
                // Ask iOS to wake MIND in ~6h so the CloudKit mirror
                // pulls any captures made on the user's other devices
                // even if they don't reopen this app today.
                BackgroundRefreshScheduler.scheduleNext()
            case .inactive:
                break
            @unknown default:
                break
            }
        }
    }

    /// Registers the `BGAppRefreshTask` handler with iOS so the system
    /// can wake MIND silently every ~6h to pull CloudKit changes. The
    /// handler does a single `mainContext.save()` (cheap when there's
    /// nothing pending) which nudges NSPersistentCloudKitContainer to
    /// check the remote zone, then immediately schedules the next
    /// wake before reporting completion.
    ///
    /// Must run during `App.init` (before the first `.active`
    /// scenePhase) — registering later raises
    /// `BGTaskSchedulerErrorDomain` 1.
    private func bootstrapBackgroundRefresh() {
        BackgroundRefreshScheduler.register { task in
            Task { @MainActor in
                let context = GraphCore.sharedContainer.mainContext
                if context.hasChanges {
                    do {
                        try context.save()
                        MINDTelemetry.info("graph.background.save")
                    } catch {
                        MINDTelemetry.error(
                            "graph.background.save.failed",
                            data: ["error": String(describing: error)]
                        )
                    }
                }
                // Always reschedule before reporting completion —
                // otherwise the wake cycle dies after one fire.
                BackgroundRefreshScheduler.scheduleNext()
                task.setTaskCompleted(true)
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

    /// Drains the cross-process `ShareInbox` queue populated by the
    /// MINDShareExtension target. Every payload becomes a `capture`
    /// Node (with `sourceURL` set when the share carried a URL), and
    /// known SaaS hosts auto-create or attach a sibling `client` Node
    /// so the capture lands in the right bucket from day one.
    ///
    /// Runs on every `.active` scenePhase transition. If the queue is
    /// empty (typical case), it's a single read of a 2-byte file — no
    /// measurable cost.
    @MainActor
    private func drainShareInbox() {
        let payloads = ShareInbox.drain()
        guard !payloads.isEmpty else { return }

        let context = GraphCore.sharedContainer.mainContext

        for payload in payloads {
            let node = Node(
                kind: .capture,
                title: payload.titleCandidate,
                content: payload.contentBody,
                sourceURL: payload.url?.absoluteString
            )
            context.insert(node)
            node.refreshEmbedding()

            // Known SaaS host? Surface (and reuse) a `client` Node so
            // the capture is filed alongside the existing audit / notes
            // the user keeps on that brand.
            if let url = payload.url,
               let clientName = ShareInbox.knownClientName(for: url) {
                _ = clientNode(named: clientName, in: context)
            }

            MINDTelemetry.info(
                "share.inbox.captured",
                data: [
                    "hasURL": payload.url != nil ? "1" : "0",
                    "knownClient": payload.url.flatMap {
                        ShareInbox.knownClientName(for: $0)
                    } ?? "none",
                ]
            )
        }

        do {
            try context.save()
        } catch {
            MINDTelemetry.error(
                "share.inbox.save.failed",
                data: ["error": String(describing: error)]
            )
        }
    }

    /// Find-or-create helper for the brand-name `client` Node used by
    /// the Share Extension capture flow. Title match is case-insensitive
    /// (covers "Stripe" vs "stripe"). Returns the canonical Node so
    /// callers can attach edges if they want to.
    @MainActor
    private func clientNode(
        named name: String,
        in context: ModelContext
    ) -> Node {
        let lowerName = name.lowercased()
        let clientRaw = NodeKind.client.rawValue
        let descriptor = FetchDescriptor<Node>(
            predicate: #Predicate { $0.kindRaw == clientRaw }
        )
        if let existing = try? context.fetch(descriptor)
            .first(where: { $0.title.lowercased() == lowerName }) {
            return existing
        }
        let new = Node(kind: .client, title: name)
        context.insert(new)
        return new
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
