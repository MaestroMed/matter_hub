import SwiftUI
import SwiftData
import AppIntents
import DesignSystem
import GraphCore
import MINDIntents
import OutreachKit
import Sentry
import Settings

/// v1.0-alpha.1 — Cockpit Studio pivot. Stripped lifecycle to the
/// hooks the rebuild keeps using: foreground CloudKit refresh,
/// background refresh scheduler registration, follow-up sequence
/// rescheduling, and Sentry bootstrap. Every share-extension drain,
/// reminders sync, daily-brief scheduler, and meeting-brief refresh
/// call from the pre-pivot era is gone alongside the modules they
/// reached.
@main
struct MINDApp: App {
    // Forces MINDAppShortcuts (and therefore RunAuditIntent) to be
    // linked into the main binary so the App Intents metadata
    // processor can extract them and iOS can surface them in Siri,
    // Spotlight, Shortcuts and the Action Button.
    static let shortcutsProvider = MINDAppShortcuts.self

    @Environment(\.scenePhase) private var scenePhase

    init() {
        bootstrapSentry()
        bootstrapBackgroundRefresh()
        // v0.29 — Drain the persisted FollowUpStore and re-queue
        // every active sequence's pending touches. Covers the case
        // where the user granted notification permission after a
        // sequence was created, OR rebooted the device, OR upgraded
        // the OS — every reschedule pass is idempotent because the
        // scheduler uses stable identifiers per touch.
        Task { @MainActor in
            await FollowUpScheduler.rescheduleAll()
        }
        // v1.0-alpha.2 — Seed the 5 real Numelite projects on first
        // launch so the Cockpit lands with Mehdi's actual portfolio
        // populated. Idempotent + gated on `mind.demo.seeded` so a
        // wipe never re-seeds without consent. Runs after the
        // container resolves on MainActor. Routed through a `static`
        // helper so the Task closure doesn't capture `self` — `App`
        // is a value-type struct and `init` can't lend a mutating
        // reference to an escaping closure.
        Task { @MainActor in
            MINDApp.seedDemoProjectsIfNeeded()
        }
    }

    /// v1.0-alpha.2 — Seeds the 5 real Numelite Project rows the
    /// first time the app launches, then sets the
    /// `mind.demo.seeded` flag so subsequent launches no-op.
    /// `Project.seedDemoProjects(in:)` is itself idempotent (bails
    /// when any Project already exists), so this is safe to call
    /// even if the flag is somehow lost. `static` so the App init
    /// can dispatch to it from an escaping `Task` closure.
    @MainActor
    static func seedDemoProjectsIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "mind.demo.seeded") == false else { return }
        let context = GraphCore.sharedContainer.mainContext
        let inserted = Project.seedDemoProjects(in: context)
        defaults.set(true, forKey: "mind.demo.seeded")
        if inserted > 0 {
            MINDTelemetry.info(
                "project.demo.seeded",
                data: ["count": String(inserted)]
            )
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.light)
        }
        .modelContainer(GraphCore.sharedContainer)
        // v0.24.1 — Stage Manager polish. The `.commands` block wires
        // up ⌘N (New Audit) + ⌘1..⌘4 (tab switch) so MIND surfaces a
        // proper keyboard-first flow when the user attaches a Magic
        // Keyboard or runs on Mac Catalyst. The window sizing pair
        // (`defaultSize` + `windowResizability`) makes Stage Manager
        // tiles stable — the OS remembers a sensible aspect close to
        // a 4:3 iPad-portrait shape so several tiled MIND windows
        // don't collapse into matchstick widths. On iPhone (compact
        // size class) both modifiers are no-ops; the OS ignores them
        // in the absence of a windowed environment.
        .commands { StageManagerCommands() }
        .defaultSize(width: 1024, height: 768)
        .windowResizability(.contentMinSize)
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
                // v0.29 — Same idempotent reschedule pass for
                // follow-up sequences: idempotent identifiers mean
                // every active sequence's pending touches are
                // re-registered, covering permission grants made
                // while the app was backgrounded.
                Task { @MainActor in
                    await FollowUpScheduler.rescheduleAll()
                }
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
