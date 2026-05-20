import Foundation
import SwiftData

/// v1.1.0 — Persisted Lighthouse probe result. Each time the cockpit
/// fans out a Lighthouse probe (manual refresh, scheduled daily
/// snapshot, or a fresh AuditKit run) we drop one of these into the
/// graph so the project detail view can render a 30-day trend
/// sparkline per metric.
///
/// CloudKit constraints (same three rules every other `@Model` in
/// this module observes):
///   1. Every non-optional stored property carries an inline default
///      so the CloudKit-backed persistent store can boot cleanly.
///   2. `@Attribute(.unique)` on `id` survives only on Simulator —
///      CloudKit silently drops the constraint at first sync. UUID()
///      collision probability (≈ 1 in 2^122) is the real guarantee.
///   3. No to-many relationships, no inverses — the link to
///      `Project` is the scalar `projectID` UUID field. Inverse
///      relationships would force a SwiftData migration on every
///      iCloud sync and the only consumer is a `@Query` predicate
///      that already filters by `projectID`.
///
/// Scores are stored as `Int` in the 0...100 range. The `init` clamps
/// values outside that bounds defensively so a future regression
/// in the probe (e.g. PageSpeed returning 102 because of a beta API
/// change) doesn't blow up the sparkline math.
@Model
public final class LighthouseSnapshot {
    @Attribute(.unique) public var id: UUID = UUID()

    /// Wall-clock time the probe completed at. Drives the "30 jours"
    /// rolling window query in `ProjectDetailSheet` and the orphan-
    /// snapshot integrity check (snapshots older than 90 days are
    /// pruned by the background scheduler — future iteration).
    public var capturedAt: Date = Date.now

    /// Links back to the owning `Project` row. UUID instead of an
    /// `@Relationship` for the CloudKit reasons above. Same UUID
    /// shape the lead inbox writer uses for its `Lead.projectID`.
    public var projectID: UUID = UUID()

    /// Project host the probe was run against. Saved so an orphan
    /// snapshot (its `Project` row was deleted) can still surface a
    /// caption like "from www.az-construction.fr" in any future
    /// listing surface. Defaults to empty when unknown.
    public var host: String = ""

    /// `"mobile"` or `"desktop"`. Stored as a raw String for
    /// CloudKit-friendliness (same shape as `Project.stack` and
    /// `Node.pipelineStageRaw`).
    public var strategy: String = "mobile"

    /// Performance score, 0...100.
    public var performance: Int = 0

    /// Accessibility score, 0...100.
    public var accessibility: Int = 0

    /// Best-practices score, 0...100. Named without an underscore so
    /// the property reads naturally in Swift; the corresponding
    /// `LighthouseScore` field is `bestPractices` for parity.
    public var bestPractices: Int = 0

    /// SEO score, 0...100.
    public var seo: Int = 0

    /// Largest-contentful-paint, seconds.
    public var lcpSeconds: Double = 0

    /// Interaction-to-next-paint, milliseconds.
    public var inpMs: Int = 0

    /// Cumulative layout shift, unitless. Stored as a Double because
    /// CLS values < 1.0 with three decimal places carry signal — the
    /// sparkline would lose resolution if we rounded to Int.
    public var cls: Double = 0

    public init(
        id: UUID = UUID(),
        capturedAt: Date = .now,
        projectID: UUID,
        host: String = "",
        strategy: String = "mobile",
        performance: Int = 0,
        accessibility: Int = 0,
        bestPractices: Int = 0,
        seo: Int = 0,
        lcpSeconds: Double = 0,
        inpMs: Int = 0,
        cls: Double = 0
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.projectID = projectID
        self.host = host
        self.strategy = strategy
        self.performance = LighthouseSnapshot.clampScore(performance)
        self.accessibility = LighthouseSnapshot.clampScore(accessibility)
        self.bestPractices = LighthouseSnapshot.clampScore(bestPractices)
        self.seo = LighthouseSnapshot.clampScore(seo)
        self.lcpSeconds = max(0, lcpSeconds)
        self.inpMs = max(0, inpMs)
        self.cls = max(0, cls)
    }

    /// Clamps a raw score to the documented 0...100 range. Exposed
    /// `static` so the trend aggregator + the model init both share
    /// one definition.
    public static func clampScore(_ raw: Int) -> Int {
        return min(100, max(0, raw))
    }
}

/// v1.1.0 — Per-metric facet the sparkline view reads. Pure enum
/// (no @Model bookkeeping) so unit tests can exercise every branch
/// without standing up a SwiftData container.
public enum LighthouseMetric: String, CaseIterable, Sendable {
    case performance
    case accessibility
    case bestPractices
    case seo

    /// Strongly-typed accessor — feeds the trend aggregator with one
    /// numeric series per metric without hard-coding `keyPath` calls
    /// in every view.
    public func value(in snapshot: LighthouseSnapshot) -> Int {
        switch self {
        case .performance:   return snapshot.performance
        case .accessibility: return snapshot.accessibility
        case .bestPractices: return snapshot.bestPractices
        case .seo:           return snapshot.seo
        }
    }

    /// Localized cell label key — mirrors the existing
    /// `project.vercel.lighthouse.*` keys so the sparkline reuses
    /// the same vocabulary as the static score grid above it.
    public var localizationKey: String {
        switch self {
        case .performance:   return "project.lighthouse.trend.metric.perf"
        case .accessibility: return "project.lighthouse.trend.metric.a11y"
        case .bestPractices: return "project.lighthouse.trend.metric.bp"
        case .seo:           return "project.lighthouse.trend.metric.seo"
        }
    }
}

/// v1.1.0 — Pure trend aggregator. Takes a heterogeneous list of
/// snapshots and a metric, returns the daily series ready to feed a
/// SwiftUI Chart. Days with no snapshot collapse to nil so the chart
/// renders a gap, which is more honest than averaging missing data.
///
/// Behaviour locked by `LighthouseTrendAggregatorTests`:
///   - Empty input → empty output (no crash on .max on nothing).
///   - Snapshots older than `window` days are dropped.
///   - When multiple snapshots land on the same calendar day, the
///     most-recent one wins (latest snapshot of the day is the
///     "official" reading for the sparkline).
///   - The output array length matches `window` exactly, indexed
///     from oldest to most-recent so the line renders left-to-right.
public enum LighthouseTrendAggregator {

    /// One point per calendar day. `value` is nil for days with no
    /// snapshot. `day` is the start-of-day for the local calendar.
    public struct Point: Equatable, Sendable {
        public let day: Date
        public let value: Int?
        public init(day: Date, value: Int?) {
            self.day = day
            self.value = value
        }
    }

    public static func last30Days(
        _ snapshots: [LighthouseSnapshot],
        metric: LighthouseMetric = .performance,
        now: Date = .now,
        calendar: Calendar = .current,
        window: Int = 30
    ) -> [Point] {
        guard window > 0 else { return [] }
        let cal = calendar
        let endOfToday = cal.startOfDay(for: now)

        // Bucket snapshots by their start-of-day so multiple captures
        // on the same day collapse to the most-recent one.
        var byDay: [Date: LighthouseSnapshot] = [:]
        for snapshot in snapshots {
            let bucket = cal.startOfDay(for: snapshot.capturedAt)
            // Drop snapshots strictly older than the window.
            let cutoff = cal.date(byAdding: .day, value: -(window - 1), to: endOfToday) ?? endOfToday
            if bucket < cutoff { continue }
            // Drop snapshots from a future day (clock skew / dev fixture).
            if bucket > endOfToday { continue }
            if let existing = byDay[bucket] {
                if snapshot.capturedAt > existing.capturedAt {
                    byDay[bucket] = snapshot
                }
            } else {
                byDay[bucket] = snapshot
            }
        }

        var points: [Point] = []
        points.reserveCapacity(window)
        for offset in stride(from: window - 1, through: 0, by: -1) {
            guard let day = cal.date(byAdding: .day, value: -offset, to: endOfToday) else { continue }
            let snapshot = byDay[day]
            let value = snapshot.map { metric.value(in: $0) }
            points.append(Point(day: day, value: value))
        }
        return points
    }

    /// Convenience aggregator returning `(metric -> [Point])` for the
    /// four standard metrics. Reused by the sparkline grid so it can
    /// render four small charts in a single pass over `snapshots`.
    public static func last30DaysAllMetrics(
        _ snapshots: [LighthouseSnapshot],
        now: Date = .now,
        calendar: Calendar = .current,
        window: Int = 30
    ) -> [LighthouseMetric: [Point]] {
        var output: [LighthouseMetric: [Point]] = [:]
        for metric in LighthouseMetric.allCases {
            output[metric] = last30Days(
                snapshots,
                metric: metric,
                now: now,
                calendar: calendar,
                window: window
            )
        }
        return output
    }

    /// Returns the count of snapshots that fall inside the rolling
    /// window. Used by the caption row below the sparkline grid.
    public static func snapshotCount(
        _ snapshots: [LighthouseSnapshot],
        now: Date = .now,
        calendar: Calendar = .current,
        window: Int = 30
    ) -> Int {
        guard window > 0 else { return 0 }
        let cal = calendar
        let endOfToday = cal.startOfDay(for: now)
        let cutoff = cal.date(byAdding: .day, value: -(window - 1), to: endOfToday) ?? endOfToday
        return snapshots.filter { snapshot in
            let bucket = cal.startOfDay(for: snapshot.capturedAt)
            return bucket >= cutoff && bucket <= endOfToday
        }.count
    }

    /// Most-recent snapshot in the window or nil if empty. Used by
    /// the "Dernier snapshot {time ago}" caption.
    public static func mostRecent(
        _ snapshots: [LighthouseSnapshot],
        window: Int = 30,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> LighthouseSnapshot? {
        guard window > 0 else { return nil }
        let cal = calendar
        let endOfToday = cal.startOfDay(for: now)
        let cutoff = cal.date(byAdding: .day, value: -(window - 1), to: endOfToday) ?? endOfToday
        return snapshots
            .filter { $0.capturedAt >= cutoff }
            .max(by: { $0.capturedAt < $1.capturedAt })
    }
}
