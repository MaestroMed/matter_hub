import Foundation

/// v0.32 — Pure side-by-side comparison of 2–4 archived
/// `AuditReport`s. Derived once from a list of reports, then consumed
/// by the App's `ComparisonSheet` view (table + overlap section + PDF
/// export). Value type all the way down so the derivation is testable
/// without UI scaffolding and the comparison can cross
/// SwiftUI ↔ rendering ↔ test boundaries with no isolation friction.
///
/// Design intent
/// -------------
/// - **2–4 reports**: the comparison only makes sense for at least 2
///   reports and tops out at 4 to keep the side-by-side layout
///   readable on an iPhone screen. The builder clamps any input
///   silently — passing 5 reports keeps the first 4, passing 1 returns
///   an empty comparison.
/// - **6 metrics per report**: same axes as `BattleReport.Metric` so
///   the Battle Mode radar logic and the comparison sheet stay in
///   visual lockstep.
/// - **Quick Wins overlap**: title equality (case-folded, whitespace-
///   trimmed) is the de-duplication key. Same Quick Win title from
///   Claude across two reports is the signal Mehdi cares about — "all
///   three SaaS prospects need to fix their HSTS header" is exactly
///   the cross-client pattern this surface is designed to surface.
/// - **Hidden Risks differences**: titles unique to a single report
///   are the differentiators. The list is sorted by report order so
///   the sheet renders the same client column-stack as the metric
///   table.
/// - **Pure**: the builder takes `[AuditReport]` and returns
///   `AuditComparison`. No async, no actor, no network — testable
///   end-to-end in microseconds.
public struct AuditComparison: Sendable, Hashable {

    /// Minimum number of reports needed for a comparison to be
    /// meaningful. Below this the builder returns an empty comparison
    /// and the UI renders a "select at least 2 audits" hint.
    public static let minimumReports = 2

    /// Maximum number of reports the comparison table can fit. Above
    /// this the builder silently truncates to the first 4.
    public static let maximumReports = 4

    /// The reports backing this comparison, in selection order. The
    /// UI renders the columns / rows in this same order.
    public let reports: [AuditReport]

    /// Per-metric score for each report, in `reports` order. Always
    /// the same length as `reports` for every metric, even when a
    /// report scored 0 on the axis.
    public let metricMatrix: [Metric: [Int]]

    /// Per-metric leader (index into `reports`). Missing when every
    /// participant scored 0 on the axis or `reports.count < 2`. Ties
    /// are broken deterministically by selection order (first wins).
    public let leaders: [Metric: Int]

    /// Quick wins that appear in 2+ reports, keyed by case-folded
    /// trimmed title. Each entry carries the original title (from the
    /// first report it was seen in) plus the list of report indices
    /// where it appeared, in `reports` order. Sorted by descending
    /// occurrence count then by title for deterministic rendering.
    public let quickWinOverlap: [OverlapEntry]

    /// Hidden risks unique to a single report (i.e. risks the other
    /// reports don't have). Keyed by case-folded trimmed title. Each
    /// entry carries the original title + the single report index +
    /// the severity. Sorted by descending severity then by title.
    public let uniqueHiddenRisks: [UniqueRiskEntry]

    public init(
        reports: [AuditReport],
        metricMatrix: [Metric: [Int]],
        leaders: [Metric: Int],
        quickWinOverlap: [OverlapEntry],
        uniqueHiddenRisks: [UniqueRiskEntry]
    ) {
        self.reports = reports
        self.metricMatrix = metricMatrix
        self.leaders = leaders
        self.quickWinOverlap = quickWinOverlap
        self.uniqueHiddenRisks = uniqueHiddenRisks
    }

    /// True when the comparison has no reports (or only 1 — below the
    /// `minimumReports` floor). The UI uses this to render the
    /// "select at least 2 audits" hint instead of the table.
    public var isEmpty: Bool {
        reports.count < Self.minimumReports
    }

    // MARK: - Nested types

    /// Comparison axes — same set as `BattleReport.Metric` so the
    /// two surfaces stay in visual lockstep. Re-declared here (not
    /// aliased) so AuditComparison stays self-describing for
    /// consumers that don't import the Battle Mode types.
    public enum Metric: String, Sendable, CaseIterable, Hashable {
        case overall
        case performance
        case seo
        case security
        case brand
        case mobile

        /// French human label used by the ComparisonSheet header row.
        public var label: String {
            switch self {
            case .overall:     return "Global"
            case .performance: return "Performance"
            case .seo:         return "SEO"
            case .security:    return "Sécurité"
            case .brand:       return "Brand"
            case .mobile:      return "Mobile"
            }
        }
    }

    /// One Quick Win that appears in 2+ reports.
    public struct OverlapEntry: Sendable, Hashable, Identifiable {
        public let id: String  // case-folded trimmed title (stable key)
        public let title: String
        public let reportIndices: [Int]

        public init(id: String, title: String, reportIndices: [Int]) {
            self.id = id
            self.title = title
            self.reportIndices = reportIndices
        }

        /// Convenience for the UI — number of reports this win
        /// appeared in.
        public var occurrenceCount: Int { reportIndices.count }
    }

    /// One Hidden Risk that appears in exactly one report.
    public struct UniqueRiskEntry: Sendable, Hashable, Identifiable {
        public let id: String  // case-folded trimmed title (stable key)
        public let title: String
        public let reportIndex: Int
        public let severity: AuditReport.HiddenRisk.Severity

        public init(
            id: String,
            title: String,
            reportIndex: Int,
            severity: AuditReport.HiddenRisk.Severity
        ) {
            self.id = id
            self.title = title
            self.reportIndex = reportIndex
            self.severity = severity
        }
    }
}

// MARK: - Builder

/// Pure namespace that turns a list of reports into an
/// `AuditComparison`. Exposed as `enum` so callers can't instantiate
/// it — the only entry point is `AuditComparisonBuilder.build(from:)`.
public enum AuditComparisonBuilder {

    /// Build a comparison from up to 4 reports. Returns an empty
    /// comparison (everything default) when fewer than
    /// `AuditComparison.minimumReports` are provided. Silently
    /// truncates to `AuditComparison.maximumReports` when more than
    /// 4 are passed.
    public static func build(from reports: [AuditReport]) -> AuditComparison {
        let clipped = Array(reports.prefix(AuditComparison.maximumReports))
        guard clipped.count >= AuditComparison.minimumReports else {
            return AuditComparison(
                reports: clipped,
                metricMatrix: [:],
                leaders: [:],
                quickWinOverlap: [],
                uniqueHiddenRisks: []
            )
        }
        return AuditComparison(
            reports: clipped,
            metricMatrix: buildMatrix(from: clipped),
            leaders: buildLeaders(from: clipped),
            quickWinOverlap: buildOverlap(from: clipped),
            uniqueHiddenRisks: buildUniqueRisks(from: clipped)
        )
    }

    /// Pure single-metric extractor — same shape as
    /// `BattleReport.scoreValue(_:in:)` so the two surfaces stay in
    /// lockstep. Re-declared here so AuditComparison's derivation
    /// stays self-contained.
    public static func scoreValue(
        _ metric: AuditComparison.Metric,
        in scoring: AuditReport.Scoring
    ) -> Int {
        switch metric {
        case .overall:     return scoring.overall
        case .performance: return scoring.performance
        case .seo:         return scoring.seo
        case .security:    return scoring.security
        case .brand:       return scoring.brand
        case .mobile:      return scoring.mobile
        }
    }

    // MARK: - Private derivations

    private static func buildMatrix(
        from reports: [AuditReport]
    ) -> [AuditComparison.Metric: [Int]] {
        var matrix: [AuditComparison.Metric: [Int]] = [:]
        for metric in AuditComparison.Metric.allCases {
            matrix[metric] = reports.map { scoreValue(metric, in: $0.scoring) }
        }
        return matrix
    }

    private static func buildLeaders(
        from reports: [AuditReport]
    ) -> [AuditComparison.Metric: Int] {
        var leaders: [AuditComparison.Metric: Int] = [:]
        for metric in AuditComparison.Metric.allCases {
            var bestScore = -1
            var bestIndex: Int?
            for (idx, report) in reports.enumerated() {
                let score = scoreValue(metric, in: report.scoring)
                // Strict `>` keeps the first-wins tie break.
                if score > bestScore {
                    bestScore = score
                    bestIndex = idx
                }
            }
            // Omit the metric entirely when every participant scored
            // 0 — the UI renders an em-dash in the leader column and
            // doesn't highlight any cell.
            if let bestIndex, bestScore > 0 {
                leaders[metric] = bestIndex
            }
        }
        return leaders
    }

    private static func buildOverlap(
        from reports: [AuditReport]
    ) -> [AuditComparison.OverlapEntry] {
        // Map normalized title → (original first-seen title, [report
        // index]). Preserves first-seen casing so the UI renders the
        // title exactly as Claude wrote it the first time, not in a
        // lowercased form.
        var seen: [String: (title: String, indices: [Int])] = [:]
        for (idx, report) in reports.enumerated() {
            // Dedup inside a single report (defensive — Claude
            // sometimes returns near-identical wins). The check uses
            // the normalized key so "Add HSTS" + "add hsts " count
            // as one within the same report.
            var seenInThisReport = Set<String>()
            for win in report.quickWins {
                let key = normalize(win.title)
                guard !key.isEmpty, !seenInThisReport.contains(key) else { continue }
                seenInThisReport.insert(key)
                if var entry = seen[key] {
                    entry.indices.append(idx)
                    seen[key] = entry
                } else {
                    seen[key] = (title: win.title, indices: [idx])
                }
            }
        }
        let overlaps = seen
            .filter { $0.value.indices.count >= 2 }
            .map { key, value in
                AuditComparison.OverlapEntry(
                    id: key,
                    title: value.title,
                    reportIndices: value.indices.sorted()
                )
            }
        // Sort by descending occurrence count, then by title for
        // deterministic rendering across runs / tests.
        return overlaps.sorted { lhs, rhs in
            if lhs.occurrenceCount != rhs.occurrenceCount {
                return lhs.occurrenceCount > rhs.occurrenceCount
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private static func buildUniqueRisks(
        from reports: [AuditReport]
    ) -> [AuditComparison.UniqueRiskEntry] {
        // Same normalize-key strategy as overlap.
        var seen: [String: (
            title: String,
            indices: [Int],
            severity: AuditReport.HiddenRisk.Severity
        )] = [:]
        for (idx, report) in reports.enumerated() {
            var seenInThisReport = Set<String>()
            for risk in report.hiddenRisks {
                let key = normalize(risk.title)
                guard !key.isEmpty, !seenInThisReport.contains(key) else { continue }
                seenInThisReport.insert(key)
                if var entry = seen[key] {
                    entry.indices.append(idx)
                    // Keep the highest severity seen — a risk
                    // appearing in two reports as `.medium` + `.high`
                    // should surface as `.high` in the differential
                    // (even though it's not unique). The downstream
                    // filter throws non-uniques away anyway, so
                    // bookkeeping severity here only matters when the
                    // risk turns out to be unique to one report.
                    if rank(of: risk.severity) > rank(of: entry.severity) {
                        entry.severity = risk.severity
                    }
                    seen[key] = entry
                } else {
                    seen[key] = (
                        title: risk.title,
                        indices: [idx],
                        severity: risk.severity
                    )
                }
            }
        }
        let unique = seen
            .filter { $0.value.indices.count == 1 }
            .compactMap { key, value -> AuditComparison.UniqueRiskEntry? in
                guard let idx = value.indices.first else { return nil }
                return AuditComparison.UniqueRiskEntry(
                    id: key,
                    title: value.title,
                    reportIndex: idx,
                    severity: value.severity
                )
            }
        // Sort by descending severity, then by title for
        // deterministic rendering.
        return unique.sorted { lhs, rhs in
            let lRank = rank(of: lhs.severity)
            let rRank = rank(of: rhs.severity)
            if lRank != rRank { return lRank > rRank }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    /// Case-folded, whitespace-trimmed normalization key. Public so
    /// tests can lock the contract — two Quick Wins with the same
    /// title modulo casing + leading/trailing whitespace must collide.
    public static func normalize(_ title: String) -> String {
        title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    /// Severity rank used for sort ordering. `critical` > `high` >
    /// `medium` > `low`. Pure for testability.
    public static func rank(of severity: AuditReport.HiddenRisk.Severity) -> Int {
        switch severity {
        case .low:      return 0
        case .medium:   return 1
        case .high:     return 2
        case .critical: return 3
        }
    }
}
