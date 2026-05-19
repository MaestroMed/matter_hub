import Foundation
#if canImport(BackgroundTasks)
import BackgroundTasks
#endif

/// Wakes MIND every ~6 hours so SwiftData / NSPersistentCloudKitContainer
/// can pull the latest changes from the user's private CloudKit zone
/// silently — no UI, no notification, just a tiny `mainContext.save()`
/// that nudges the mirror to look for remote work.
///
/// Why
/// ---
/// CloudKit only mirrors on demand: when the app is foregrounded, when
/// `save()` is called on the model context, or when a remote
/// notification fires. Without a periodic kick, a user who opens MIND
/// only once a day can see graph state that's 24h stale — capture made
/// on iPhone yesterday won't appear on iPad until they re-open the
/// iPhone app. `BGAppRefreshTask` solves that without draining battery:
/// iOS decides when to fire based on usage patterns, capped at ~30s of
/// work per fire.
///
/// Wiring contract
/// ----------------
///   1. `MINDApp.init()` calls `register()` once at boot to teach the
///      system about the identifier.
///   2. `MINDApp.onChange(of: scenePhase == .background)` calls
///      `scheduleNext()` so iOS has a pending request to satisfy.
///   3. The system fires the handler in the background; the handler
///      saves the main context (idempotent / cheap) then immediately
///      schedules the next one before completing.
///
/// The identifier must match the entry in
/// `Info.plist → BGTaskSchedulerPermittedIdentifiers` — that wiring
/// lives in `Project.swift`.
public enum BackgroundRefreshScheduler {

    /// Identifier kept in lockstep with `Info.plist`. Hardcoded as a
    /// constant so any consumer (and any test) imports the same string
    /// — no chance of a typo silently disabling the wake cycle.
    public static let taskIdentifier = "app.mind.ios.refresh"

    /// Earliest time at which iOS is allowed to wake MIND, expressed
    /// as seconds from "now". 6 hours is a sweet spot between
    /// freshness and battery: a casual user opens MIND 2-4 times a
    /// day, so 6h lines up with "wake before next session". iOS may
    /// fire later (it batches background work) but never earlier.
    public static let refreshInterval: TimeInterval = 6 * 60 * 60

    /// Registers the handler with `BGTaskScheduler`. Must be called
    /// before the SwiftUI scene phase reaches `.active` — i.e. from
    /// `MINDApp.init()` — otherwise the system rejects later
    /// `submit(...)` calls with a "no handler registered" error.
    ///
    /// `handler` is the work the system runs while MIND is in the
    /// background. Keep it short (well under the ~30s budget): one
    /// `mainContext.save()` is enough to wake the CloudKit mirror.
    /// The handler MUST schedule the next refresh before completing,
    /// otherwise the wake cycle dies.
    ///
    /// Returns `true` on a successful registration, `false` when
    /// the system refused (typically: identifier missing from
    /// Info.plist, or running in an unsupported environment like
    /// the unit-test bundle). Tests rely on the no-op return so they
    /// can assert the function is idempotent without crashing.
    @discardableResult
    public static func register(
        handler: @Sendable @escaping (_ task: BackgroundRefreshTask) -> Void
    ) -> Bool {
        #if canImport(BackgroundTasks) && !targetEnvironment(simulator)
        return BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { bgTask in
            handler(BackgroundRefreshTask(bgTask: bgTask))
        }
        #else
        // Simulator + macOS unit-test bundle: no BackgroundTasks
        // daemon, so registration is a no-op. The scenePhase / save
        // path still works on device, where it matters.
        _ = handler
        return false
        #endif
    }

    /// Asks `BGTaskScheduler` to fire the registered handler no
    /// sooner than `refreshInterval` from now. Idempotent — calling
    /// it twice in a row simply overrides the previous request.
    /// Silently swallows errors; missing scheduling is not a crash
    /// path, just a missed wake cycle.
    public static func scheduleNext(now: Date = .now) {
        #if canImport(BackgroundTasks) && !targetEnvironment(simulator)
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = nextEarliestBeginDate(from: now)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // BGTaskSchedulerErrorDomain failures (unavailable, too
            // many pending, etc.) are non-fatal — iOS will let us
            // retry on the next backgrounding.
        }
        #else
        _ = nextEarliestBeginDate(from: now)
        #endif
    }

    /// Pure-function helper used by `scheduleNext` and exercised by
    /// tests — keeps the date math out of the `#if canImport`
    /// branches so it stays deterministic regardless of target.
    public static func nextEarliestBeginDate(from now: Date) -> Date {
        now.addingTimeInterval(refreshInterval)
    }
}

/// Thin wrapper around `BGTask` so the handler signature doesn't leak
/// the BackgroundTasks framework into call sites. Lets the app layer
/// finish the task without importing `BackgroundTasks` directly, and
/// keeps the test surface mockable (we can build a fake one if a
/// future test needs to drive the handler manually).
public struct BackgroundRefreshTask: Sendable {
    /// True when the system has signalled an early termination —
    /// the handler must call `setTaskCompleted(success:)` ASAP.
    public let isExpired: @Sendable () -> Bool

    /// Reports back to iOS whether the wake produced useful work.
    /// `false` discourages the scheduler from firing as eagerly on
    /// the next cycle.
    public let setTaskCompleted: @Sendable (_ success: Bool) -> Void

    /// Designated initialiser for production use, wrapping a real
    /// `BGTask` from the BackgroundTasks framework.
    #if canImport(BackgroundTasks)
    init(bgTask: BGTask) {
        // BGTask itself isn't Sendable, so we read the boxed reference
        // through an UncheckedSendable shim and only ever touch it
        // from the BackgroundTasks-supplied queue.
        let box = UncheckedSendableBox(value: bgTask)
        self.isExpired = { false }  // BGTask exposes `expirationHandler`
                                    // but not a queryable bool; tests
                                    // override via `init(isExpired:...)`.
        self.setTaskCompleted = { success in
            box.value.setTaskCompleted(success: success)
        }
    }
    #endif

    /// Memberwise initialiser exposed for unit tests so the handler
    /// can be driven without the BackgroundTasks runtime.
    public init(
        isExpired: @Sendable @escaping () -> Bool = { false },
        setTaskCompleted: @Sendable @escaping (_ success: Bool) -> Void = { _ in }
    ) {
        self.isExpired = isExpired
        self.setTaskCompleted = setTaskCompleted
    }
}

/// `BGTask` is a non-Sendable reference type but the BackgroundTasks
/// framework guarantees a single-queue delivery contract for the
/// handler callback. Wrapping it in an UncheckedSendable struct lets
/// the closure capture survive Swift 6's strict concurrency checks
/// without unsafely retyping every consumer.
private struct UncheckedSendableBox<Value>: @unchecked Sendable {
    let value: Value
}
