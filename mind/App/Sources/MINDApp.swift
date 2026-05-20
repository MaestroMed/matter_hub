import SwiftUI
import SwiftData
import AppIntents
import DesignSystem
import GraphCore
import MINDIntents
import OutreachKit
import Sentry
import Settings
// v1.0-alpha.14 — APNs Notification Service Extension wiring. Both
// imports are needed unconditionally (iPhone needs the
// `UIApplicationDelegateAdaptor` for the device-token callbacks) so
// the targetEnvironment-gated import block below is dropped.
import UIKit
import UserNotifications
// v1.0-alpha.19 — Vision Pro spatial cockpit. `VisionSpatialKit`
// exposes `SpatialTelemetryBridge` on every platform (so the iOS
// host can wire its sink at bootstrap) and the visionOS-only
// SwiftUI surfaces (`SpatialRootView`, `SpatialAuditTheaterImmersive`)
// behind `#if os(visionOS)`.
import VisionSpatialKit

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

    // v1.0-alpha.14 — APNs Notification Service Extension wiring.
    // The adaptor lets SwiftUI hand back the legacy
    // `UIApplicationDelegate` callbacks iOS still routes
    // device-token registration through, plus the foreground
    // notification + tap handlers.
    @UIApplicationDelegateAdaptor(MINDPushDelegate.self) private var pushDelegate

    @Environment(\.scenePhase) private var scenePhase

    init() {
        bootstrapSentry()
        bootstrapBackgroundRefresh()
        bootstrapSpatialTelemetry()
        // v1.0-alpha.17 — Activate the WatchConnectivity bridge from
        // the iPhone side. Soft-fails on unsupported platforms
        // (Mac Catalyst, iPad without a paired Watch) so the call is
        // always safe — `WCSession.isSupported()` returns false there
        // and the bridge no-ops. The Watch-side `focus.start`/`focus.end`
        // handlers stay nil for v1.0-alpha.17 (host-side focus surface
        // is a follow-up); the bridge still receives the messages and
        // routes them through the registered handlers when they land.
        WatchConnectivityBridge.shared.activatePhoneSide()
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
            // v1.0-alpha.3 — Seed demo Leads right after Projects so
            // HomeView's "Aujourd'hui" inbox lands populated on first
            // launch. Order matters: the lead seed looks up its
            // owning Project by exact name.
            MINDApp.seedDemoLeadsIfNeeded()
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

    /// v1.0-alpha.3 — Seeds 4 demo Lead rows on first launch so the
    /// new HomeView inbox isn't empty before any real webhook lands.
    /// Idempotent + gated on `mind.demoLeads.seeded`. Skips silently
    /// when the projects aren't there yet (e.g. seeding disabled in
    /// debug) — `Lead.seedDemoLeads(in:)` itself guards on Project
    /// presence.
    @MainActor
    static func seedDemoLeadsIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "mind.demoLeads.seeded") == false else { return }
        let context = GraphCore.sharedContainer.mainContext
        let inserted = Lead.seedDemoLeads(in: context)
        // Only set the flag when the seed actually inserted rows. A
        // 0-row return (no projects yet, or leads already present)
        // leaves the flag unset so the next cold launch retries.
        if inserted > 0 {
            defaults.set(true, forKey: "mind.demoLeads.seeded")
            MINDTelemetry.info(
                "lead.demo.seeded",
                data: ["count": String(inserted)]
            )
        }
    }

    /// v1.0-alpha.16 — Hands a fresh cockpit snapshot to the App
    /// Group suite so the iOS 26 Lock Screen widgets + StandBy
    /// dashboard surface the same lead count / MRR / critical-project
    /// columns HomeView shows. Called on every `.active` scene phase.
    ///
    /// Source columns:
    ///  - `leadCount`            = `Lead` rows with `status == "new"`
    ///  - `leadLastContact`      = most-recent (`receivedAt` desc)
    ///                              new lead's contact name
    ///  - `totalMRR`             = `ProjectMRR.total(of:)` over every
    ///                              active retainer Project
    ///  - `criticalProjectName`  = nil — wired in a future iteration
    ///                              once the host can stream the
    ///                              `PortfolioHealthAggregator` snapshot
    ///                              over the App Group bridge without
    ///                              the heavy CloudKit reach. For
    ///                              v1.0-alpha.16 the column starts
    ///                              empty; the widget's deployment
    ///                              status row collapses to the "all
    ///                              green" branch via the formatter.
    ///
    /// Soft-fail: SwiftData fetch failures + an empty graph both
    /// collapse to zeroed columns. The `SharedSnapshotWriter` itself
    /// is the only allowed side-effect — no telemetry hop in here
    /// keeps the call site cheap on every wake.
    @MainActor
    static func refreshWidgetSnapshot() {
        let context = GraphCore.sharedContainer.mainContext

        let leadDescriptor = FetchDescriptor<Lead>(
            predicate: #Predicate<Lead> { $0.status == "new" },
            sortBy: [SortDescriptor(\Lead.receivedAt, order: .reverse)]
        )
        let newLeads = (try? context.fetch(leadDescriptor)) ?? []

        let projectDescriptor = FetchDescriptor<Project>()
        let projects = (try? context.fetch(projectDescriptor)) ?? []
        let mrr = ProjectMRR.total(of: projects)

        let headContact: String? = {
            guard let first = newLeads.first else { return nil }
            let name = first.contactName.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? nil : name
        }()

        SharedSnapshotWriter.refresh(
            leadCount: newLeads.count,
            leadLastContact: headContact,
            totalMRR: mrr,
            criticalProjectName: nil
        )
        MINDTelemetry.info(
            "widget.snapshot.refreshed",
            data: [
                "leads": String(newLeads.count),
                "mrr": String(mrr),
            ]
        )

        // v1.0-alpha.17 — Hand the same numbers to the Apple Watch
        // via `WatchConnectivityBridge`. Same offline-first contract
        // as the widget refresh: pushes write to the shared App Group
        // first (so the Watch surfaces the latest snapshot whether or
        // not the session is reachable), then attempts a live
        // sendMessage. Lead digests are clipped to the 5 most-recent
        // new leads so the Watch payload stays under WCSession's
        // ~64 KB envelope budget.
        let digestLeads: [WatchLeadDigest] = newLeads.prefix(5).map { lead in
            WatchLeadDigest(
                id: lead.id,
                contactName: lead.contactName,
                messagePreview: lead.message,
                receivedAtMillis: Int64(lead.receivedAt.timeIntervalSince1970 * 1_000)
            )
        }
        WatchConnectivityBridge.shared.pushLeadsSnapshot(digestLeads)
        WatchConnectivityBridge.shared.pushPortfolioKPI(
            WatchPortfolioKPI(
                leadsToday: newLeads.count,
                mrrEUR: mrr,
                buildErrors: 0
            )
        )
    }

    var body: some Scene {
        #if os(visionOS)
        // v1.0-alpha.19 — Vision Pro spatial cockpit. The visionOS
        // slice ships a volumetric `WindowGroup` of the
        // `SpatialRootView` (Leads / Projects / Audits TabView, every
        // panel built on `.ultraThinMaterial` + `glassBackgroundEffect()`),
        // plus the `AuditTheater` `ImmersiveSpace` the user opens from
        // a finished audit. Both compile only when the visionOS slice
        // is targeted; iOS / iPad / Mac Catalyst fall through to the
        // standard `RootView`.
        WindowGroup(id: SpatialAuditTheater.immersiveSpaceID + ".main") {
            SpatialRootView()
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 1.2, height: 0.8, depth: 0.3, in: .meters)
        .modelContainer(GraphCore.sharedContainer)

        ImmersiveSpace(id: SpatialAuditTheater.immersiveSpaceID) {
            SpatialAuditTheaterImmersive()
        }
        #else
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
                MINDTelemetry.info("mac.scenePhase.active")
                refreshGraphFromCloud()
                // v1.0-alpha.12 — Refresh the Mac dock badge on every
                // foreground so a lead that arrived while MIND was
                // backgrounded surfaces immediately on the dock icon.
                refreshDockBadge()
                // v1.0-alpha.16 — Hand the freshest cockpit snapshot
                // to the App Group suite (`group.app.mind.ios`) so
                // the iOS 26 Lock Screen widgets + StandBy dashboard
                // pull the same lead count / MRR / critical-project
                // columns HomeView shows. Cheap: a single SwiftData
                // fetch + four UserDefaults writes + one
                // `WidgetCenter.shared.reloadAllTimelines()` nudge.
                // Runs on the MainActor because both the SwiftData
                // read and `SharedSnapshotWriter` itself are
                // MainActor-bound.
                MINDApp.refreshWidgetSnapshot()
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
                MINDTelemetry.info("mac.scenePhase.background")
                // Ask iOS to wake MIND in ~6h so the CloudKit mirror
                // pulls any captures made on the user's other devices
                // even if they don't reopen this app today.
                BackgroundRefreshScheduler.scheduleNext()
            case .inactive:
                MINDTelemetry.info("mac.scenePhase.inactive")
            @unknown default:
                break
            }
        }
        #endif
    }

    /// v1.0-alpha.12 — Updates the Mac Catalyst dock badge with the
    /// count of new leads. On iPhone / iPad the dock badge concept
    /// doesn't apply (the home-screen icon badge path goes through
    /// `UNUserNotificationCenter.setBadgeCount` instead), so the
    /// implementation is gated behind a Catalyst-only compile flag.
    @MainActor
    private func refreshDockBadge() {
        #if targetEnvironment(macCatalyst)
        let context = GraphCore.sharedContainer.mainContext
        let descriptor = FetchDescriptor<Lead>(
            predicate: #Predicate<Lead> { $0.status == "new" }
        )
        let leads = (try? context.fetch(descriptor)) ?? []
        let count = MacDockBadge.displayCount(forNewLeads: leads.count)
        UNUserNotificationCenter.current().setBadgeCount(count) { _ in }
        MINDTelemetry.info(
            "mac.dockBadge.updated",
            data: ["count": String(count)]
        )
        #endif
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

    /// v1.0-alpha.19 — Wires the visionOS spatial cockpit's telemetry
    /// bridge to `MINDTelemetry`. Every breadcrumb the spatial views
    /// emit (`spatial.app.launched`, `spatial.tab.changed`,
    /// `spatial.audit.theater.opened`, …) routes through the same
    /// Sentry sink as every other module. Safe to call on iOS — the
    /// bridge type compiles on every platform; only the visionOS
    /// surfaces themselves are gated.
    private func bootstrapSpatialTelemetry() {
        SpatialTelemetryBridge.shared.sink = { event in
            Task { @MainActor in
                MINDTelemetry.info(event.name, data: event.data)
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
            options.releaseName = "MIND@1.0.0"
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
                data: ["release": "MIND@1.0.0"]
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

// MARK: - APNs (v1.0-alpha.14)

/// v1.0-alpha.14 — Adapter that routes APNs / UNUserNotificationCenter
/// callbacks back into the SwiftUI app. SwiftUI's `App` lifecycle
/// doesn't expose `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`
/// so we still need an `NSObject`-backed delegate (the only way iOS
/// reports the device-token registration result). All work delegates
/// to `PushRegistration` + `NotificationCenter.default` so the
/// delegate stays a thin wrapper.
///
/// Marked `nonisolated` (and the class itself sits outside MainActor)
/// because `UNUserNotificationCenterDelegate` is `@preconcurrency`
/// nonisolated — annotating the class @MainActor would crash the
/// Swift 6 concurrency checker on protocol conformance. Each method
/// that needs the main actor hops there via `Task { @MainActor in … }`.
final class MINDPushDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    nonisolated func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Become the user-notification delegate so we receive
        // foreground presentation + tap callbacks routed below.
        // `setDelegate` is called from the main-thread launch sequence
        // (iOS invokes didFinishLaunching there) so the cast is safe.
        Task { @MainActor in
            UNUserNotificationCenter.current().delegate = self
        }
        return true
    }

    nonisolated func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            let hex = PushRegistration.handleDeviceToken(deviceToken)
            MINDTelemetry.info(
                "apns.token.registered",
                data: ["token.prefix": String(hex.prefix(8))]
            )
        }
    }

    nonisolated func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        let description = String(describing: error)
        Task { @MainActor in
            MINDTelemetry.error(
                "apns.token.failed",
                data: ["error": description]
            )
        }
    }

    /// Foreground-presentation handler: when a lead push lands while
    /// MIND is in the foreground, still display the banner + sound so
    /// the operator notices it immediately. Without this iOS suppresses
    /// the banner entirely for foreground apps.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge, .list])
    }

    /// Tap handler. Reads the `lead.id` field decorated by
    /// `NotificationService` (the NSE) and routes it through
    /// `Notification.Name.mindOpenLead` so `HomeView` can flip its
    /// `selectedLead` state and present `LeadDetailSheet`. Falls back
    /// to no-op when the userInfo is malformed — we don't want to crash
    /// on a stray dev push.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let leadDict = (userInfo["lead"] as? [String: Any])
            ?? ((userInfo["aps"] as? [String: Any])?["payload"] as? [String: Any])
        let keys = userInfo.keys.map { "\($0)" }.joined(separator: ",")
        let idString = leadDict?["id"] as? String
        let leadID = idString.flatMap { UUID(uuidString: $0) }
        // Call completionHandler synchronously before hopping to
        // MainActor — iOS only needs to know we accepted the tap, the
        // breadcrumb + notification post happen out-of-band.
        completionHandler()
        Task { @MainActor in
            if let leadID {
                MINDTelemetry.info(
                    "push.tap.received",
                    data: ["leadID.prefix": String(leadID.uuidString.prefix(8))]
                )
                NotificationCenter.default.post(name: .mindOpenLead, object: leadID)
            } else {
                MINDTelemetry.warning(
                    "push.tap.malformed",
                    data: ["userInfo.keys": keys]
                )
            }
        }
    }
}
