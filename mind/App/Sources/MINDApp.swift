import SwiftUI
import SwiftData
import AppIntents
import DesignSystem
import GraphCore
import MINDIntents
import RemindersKit
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
                runRemindersSyncIfEnabled()
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

    /// Drains the bidirectional Reminders ↔ Tasks sync (v0.10) if the
    /// user has flipped the opt-in toggle on in Settings → Préférences
    /// AND already granted full-access reminders permission. The pure
    /// diff lives in `RemindersSyncEngine`; this method is the I/O glue
    /// that:
    ///   1. Reads task-shaped Nodes from the main context
    ///   2. Fetches the current `[ReminderSnapshot]` from EventKit
    ///   3. Plans the diff
    ///   4. Applies each action (creating reminders, minting nodes,
    ///      writing back the paired identifier, propagating field
    ///      updates each way)
    ///
    /// Skips silently when the toggle is off — EventKit is never
    /// touched in that branch so the user doesn't see a permission
    /// prompt they didn't ask for.
    @MainActor
    private func runRemindersSyncIfEnabled() {
        guard MINDPreferences.currentRemindersSyncEnabled() else { return }

        Task { @MainActor in
            // Bail early if permission was revoked from iOS Settings
            // since the last run. Soft-fail so the next foreground
            // tries again without spamming the user. Distinguish the
            // "denied / restricted" branch from "still pending" so we
            // can correlate the Sentry timeline against user intent.
            let auth = await RemindersStore.shared.currentAuthorization()
            guard auth == .fullAccess else {
                MINDTelemetry.info(
                    "reminders.access.denied",
                    data: ["status": String(describing: auth)]
                )
                return
            }

            let context = GraphCore.sharedContainer.mainContext
            let taskRaw = NodeKind.task.rawValue
            let descriptor = FetchDescriptor<Node>(
                predicate: #Predicate { $0.kindRaw == taskRaw }
            )
            let allTasks = (try? context.fetch(descriptor)) ?? []
            let projections = allTasks.compactMap { RemindersSyncEngine.NodeProjection(node: $0) }
            let nodesByID = Dictionary(uniqueKeysWithValues: allTasks.map { ($0.id, $0) })

            let snapshots = await RemindersStore.shared.fetchAll()
            let plan = RemindersSyncEngine().plan(
                nodes: projections,
                reminders: snapshots
            )

            guard !plan.isEmpty else {
                MINDTelemetry.info(
                    "reminders.sync.noop",
                    data: ["tasks": "\(projections.count)", "reminders": "\(snapshots.count)"]
                )
                return
            }

            var nodeCreates = 0
            var reminderCreates = 0
            var nodeUpdates = 0
            var reminderUpdates = 0
            var bindings = 0

            for action in plan.actions {
                switch action {
                case let .createReminderFor(nodeID, title, notes, dueDate, isCompleted):
                    if let externalID = await RemindersStore.shared.create(
                        title: title,
                        notes: notes,
                        dueDate: dueDate,
                        isCompleted: isCompleted
                    ), let node = nodesByID[nodeID] {
                        node.reminderExternalID = externalID
                        reminderCreates += 1
                    }
                case let .createNodeFor(reminderID, title, notes, _, isCompleted):
                    let node = Node(
                        kind: .task,
                        title: title,
                        content: notes ?? "",
                        tags: ["task"]
                    )
                    node.reminderExternalID = reminderID
                    if isCompleted {
                        node.completedAt = .now
                    }
                    context.insert(node)
                    node.refreshEmbedding()
                    nodeCreates += 1
                case let .updateNode(nodeID, title, notes, isCompleted):
                    guard let node = nodesByID[nodeID] else { continue }
                    node.title = title
                    node.content = notes ?? ""
                    if isCompleted && node.completedAt == nil {
                        node.completedAt = .now
                    } else if !isCompleted {
                        node.completedAt = nil
                    }
                    node.updatedAt = .now
                    nodeUpdates += 1
                case let .updateReminder(reminderID, title, notes, isCompleted):
                    await RemindersStore.shared.update(
                        id: reminderID,
                        title: title,
                        notes: notes,
                        isCompleted: isCompleted
                    )
                    reminderUpdates += 1
                case let .bindNodeToReminder(nodeID, reminderID):
                    nodesByID[nodeID]?.reminderExternalID = reminderID
                    bindings += 1
                }
            }

            do {
                try context.save()
            } catch {
                MINDTelemetry.error(
                    "reminders.sync.save.failed",
                    data: ["error": String(describing: error)]
                )
                return
            }

            MINDTelemetry.info(
                "reminders.sync.applied",
                data: [
                    "nodeCreates": "\(nodeCreates)",
                    "reminderCreates": "\(reminderCreates)",
                    "nodeUpdates": "\(nodeUpdates)",
                    "reminderUpdates": "\(reminderUpdates)",
                    "bindings": "\(bindings)",
                ]
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
