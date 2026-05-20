import Foundation
import SwiftData
import GraphCore
import ProjectHealthKit

/// v1.1.0 — Bridge actor that turns a fresh `LighthouseScore`
/// (returned from `LighthouseProbe.score(for:)`) into a persisted
/// `LighthouseSnapshot` row inside the SwiftData graph.
///
/// Lives in the App target — not in ProjectHealthKit — because the
/// SwiftData write needs access to `GraphCore.sharedContainer` and
/// ProjectHealthKit only depends on GraphCore for the telemetry
/// breadcrumbs (the kit is otherwise framework-pure). Injecting a
/// host-side bridge here keeps ProjectHealthKit free of @MainActor
/// reach and aligns with how the existing v1.0-alpha.18
/// `AuditPitchAudioStore` bridge is wired.
///
/// Rate limit: callers are expected to gate the per-day frequency.
/// `BackgroundRefreshScheduler` caps daily auto-snapshots at 5 per
/// project per day; manual taps and AuditController fan-outs are
/// always allowed to write.
@MainActor
public enum LighthouseSnapshotStore {

    /// Persists a `LighthouseScore` as a `LighthouseSnapshot`. Idempotent
    /// per-call (a new row is inserted every time — the trend aggregator
    /// dedupes by start-of-day at read time). Soft-fails the SwiftData
    /// save: on error a warning breadcrumb fires but the cockpit keeps
    /// rendering.
    public static func persist(
        score: LighthouseScore,
        projectID: UUID,
        host: String,
        strategy: LighthouseProbe.Strategy = .mobile,
        context: ModelContext? = nil
    ) {
        let target = context ?? GraphCore.sharedContainer.mainContext
        let snapshot = LighthouseSnapshot(
            id: UUID(),
            capturedAt: score.fetchedAt,
            projectID: projectID,
            host: host,
            strategy: strategy.rawValue,
            performance: score.performance,
            accessibility: score.accessibility,
            bestPractices: score.bestPractices,
            seo: score.seo,
            lcpSeconds: score.lcpSeconds,
            inpMs: score.inpMs,
            cls: score.cls
        )
        target.insert(snapshot)
        do {
            try target.save()
            MINDTelemetry.info(
                "lighthouse.snapshot.persisted",
                data: [
                    "projectID": projectID.uuidString,
                    "perf": String(score.performance),
                    "strategy": strategy.rawValue,
                ]
            )
        } catch {
            MINDTelemetry.warning(
                "lighthouse.snapshot.failed",
                data: [
                    "projectID": projectID.uuidString,
                    "error": String(describing: error),
                ]
            )
        }
    }

    /// Convenience wrapper for callers that already build their own
    /// `LighthouseSnapshot` directly (tests, the daily scheduler).
    public static func persist(
        snapshot: LighthouseSnapshot,
        context: ModelContext? = nil
    ) {
        let target = context ?? GraphCore.sharedContainer.mainContext
        target.insert(snapshot)
        do {
            try target.save()
            MINDTelemetry.info(
                "lighthouse.snapshot.persisted",
                data: [
                    "projectID": snapshot.projectID.uuidString,
                    "perf": String(snapshot.performance),
                    "strategy": snapshot.strategy,
                ]
            )
        } catch {
            MINDTelemetry.warning(
                "lighthouse.snapshot.failed",
                data: [
                    "projectID": snapshot.projectID.uuidString,
                    "error": String(describing: error),
                ]
            )
        }
    }
}
