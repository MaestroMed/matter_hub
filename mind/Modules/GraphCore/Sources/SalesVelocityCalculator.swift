import Foundation

/// v1.0-alpha.13 — Pure sales velocity math.
///
/// Powers the new HomeView "Vélocité" card + the full-screen
/// `SalesVelocitySheet`. Every helper is referentially transparent
/// (no SwiftData reads, no Date.now under the hood — every call site
/// passes `asOf:` explicitly) so the test suite locks the buckets
/// without dragging in the simulator clock.
///
/// Buckets
/// -------
/// - **MRR history** — one `MRRPoint` per calendar month from
///   `monthsBack(asOf:months:)` up to `asOf`'s month inclusive. Sums
///   the active retainer MRR (`monthlyRecurringRevenueEUR` on
///   retainer + active|maintenance projects) for the month where the
///   project's `startedAt` is on/before the month-end. Oneshot rows
///   never count — they don't recur.
/// - **Weekly leads** — one `WeeklyLeadPoint` per ISO-week from
///   `weeksBack` up to `asOf`. Counts every `Lead` whose `receivedAt`
///   falls inside the week (Monday 00:00 → Sunday 23:59:59 local).
/// - **Conversion rate** — `won / (won + lost + new + contacted +
///   qualified)` over the last N weeks. Spam excluded — it's not a
///   lead the funnel actually processed. Zero leads in window → 0.0
///   (not NaN — UI consumers crash on NaN).
/// - **Funnel distribution** — one `FunnelStagePoint` per
///   `LeadStatus` raw value, in canonical funnel order (new →
///   contacted → qualified → won → lost → spam). Count == 0 entries
///   are kept so the stacked-bar chart shows the full funnel even
///   when one stage is empty.
public enum SalesVelocityCalculator {
    /// Default month count for the HomeView card. The sheet asks for
    /// the same 12 explicitly so the surface stays predictable.
    public static let defaultMonths: Int = 12

    /// Default week count for the HomeView bar chart.
    public static let defaultWeeks: Int = 12

    /// Default look-back window for the conversion rate gauge.
    public static let defaultConversionWeeks: Int = 4

    // MARK: - MRR history

    /// Monthly MRR snapshot, one point per calendar month. Returns
    /// exactly `months` entries, oldest first, with the last entry
    /// covering `asOf`'s month. Empty `projects` → all zeros.
    public static func monthlyMRRHistory(
        projects: [Project],
        months: Int = defaultMonths,
        asOf: Date = .now
    ) -> [MRRPoint] {
        let clamped = max(1, min(60, months))
        let calendar = Calendar.frenchWeek
        let endOfMonth = calendar.startOfMonth(for: asOf)
        var points: [MRRPoint] = []
        for offset in stride(from: clamped - 1, through: 0, by: -1) {
            guard
                let monthStart = calendar.date(
                    byAdding: .month,
                    value: -offset,
                    to: endOfMonth
                )
            else { continue }
            let mrr = retainerMRR(in: projects, asOfMonth: monthStart, calendar: calendar)
            points.append(MRRPoint(monthStart: monthStart, mrrEUR: mrr))
        }
        return points
    }

    /// Sum of active retainer MRR for the given month. A project
    /// counts when it's a retainer, its lifecycle is active or
    /// maintenance, and its `startedAt` is on or before the month
    /// end. Archived / discovery projects never count.
    private static func retainerMRR(
        in projects: [Project],
        asOfMonth monthStart: Date,
        calendar: Calendar
    ) -> Int {
        guard let monthEnd = calendar.endOfMonth(for: monthStart) else { return 0 }
        return projects.reduce(0) { acc, project in
            guard project.contractTypeEnum == .retainer else { return acc }
            let stage = project.lifecycleStageEnum
            guard stage == .active || stage == .maintenance else { return acc }
            // Project must have started on or before this month-end.
            guard project.startedAt <= monthEnd else { return acc }
            return acc + max(0, project.monthlyRecurringRevenueEUR)
        }
    }

    // MARK: - Weekly leads

    /// Lead count per ISO-week. Returns exactly `weeks` entries,
    /// oldest first, with the last entry covering `asOf`'s week.
    /// Empty `leads` → all zeros.
    public static func weeklyLeads(
        leads: [Lead],
        weeks: Int = defaultWeeks,
        asOf: Date = .now
    ) -> [WeeklyLeadPoint] {
        let clamped = max(1, min(104, weeks))
        let calendar = Calendar.frenchWeek
        let endOfWeek = calendar.startOfWeek(for: asOf)
        var points: [WeeklyLeadPoint] = []
        for offset in stride(from: clamped - 1, through: 0, by: -1) {
            guard
                let weekStart = calendar.date(
                    byAdding: .weekOfYear,
                    value: -offset,
                    to: endOfWeek
                ),
                let weekEnd = calendar.endOfWeek(for: weekStart)
            else { continue }
            let count = leads.reduce(0) { acc, lead in
                lead.receivedAt >= weekStart && lead.receivedAt <= weekEnd ? acc + 1 : acc
            }
            points.append(WeeklyLeadPoint(weekStart: weekStart, count: count))
        }
        return points
    }

    // MARK: - Conversion rate

    /// Conversion rate (won / processed) over the last N weeks. Spam
    /// excluded. 0.0 when no leads landed in the window — never NaN.
    public static func conversionRate(
        leads: [Lead],
        lastWeeks: Int = defaultConversionWeeks,
        asOf: Date = .now
    ) -> Double {
        let clamped = max(1, min(52, lastWeeks))
        let calendar = Calendar.frenchWeek
        let windowEnd = asOf
        guard
            let windowStart = calendar.date(
                byAdding: .weekOfYear,
                value: -clamped,
                to: windowEnd
            )
        else { return 0.0 }
        let inWindow = leads.filter { lead in
            lead.receivedAt >= windowStart && lead.receivedAt <= windowEnd
        }
        let processed = inWindow.filter { lead in
            lead.statusEnum != .spam
        }
        guard !processed.isEmpty else { return 0.0 }
        let won = processed.filter { $0.statusEnum == .won }.count
        return Double(won) / Double(processed.count)
    }

    // MARK: - Funnel distribution

    /// One bucket per `LeadStatus` in canonical funnel order. Returns
    /// every stage even when count == 0 so the stacked-bar chart
    /// renders a stable footprint.
    public static func funnelDistribution(leads: [Lead]) -> [FunnelStagePoint] {
        let stages: [LeadStatus] = [.new, .contacted, .qualified, .won, .lost, .spam]
        return stages.map { status in
            let count = leads.reduce(0) { acc, lead in
                lead.statusEnum == status ? acc + 1 : acc
            }
            return FunnelStagePoint(stage: status.rawValue, count: count)
        }
    }
}

// MARK: - Value types

/// One MRR snapshot. `mrrEUR` is the sum-of-retainer-MRR at the end
/// of the month. Identifiable so SwiftUI's `Chart` mounts the marks
/// without juggling indices.
public struct MRRPoint: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let monthStart: Date
    public let mrrEUR: Int

    public init(id: UUID = UUID(), monthStart: Date, mrrEUR: Int) {
        self.id = id
        self.monthStart = monthStart
        self.mrrEUR = mrrEUR
    }
}

/// One weekly lead count bucket.
public struct WeeklyLeadPoint: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let weekStart: Date
    public let count: Int

    public init(id: UUID = UUID(), weekStart: Date, count: Int) {
        self.id = id
        self.weekStart = weekStart
        self.count = count
    }
}

/// One funnel-stage count bucket. `stage` is the
/// `LeadStatus.rawValue` so the SwiftUI consumer doesn't have to
/// re-localize via a custom CodingKey.
public struct FunnelStagePoint: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let stage: String
    public let count: Int

    public init(id: UUID = UUID(), stage: String, count: Int) {
        self.id = id
        self.stage = stage
        self.count = count
    }
}

// MARK: - Calendar helpers

private extension Calendar {
    /// Calendar tuned for French locale (Monday-first week). Stored
    /// as a computed property so each call gets a fresh struct copy
    /// — Calendar is a value type but allocating it per-call is the
    /// simplest way to dodge thread-locality footguns.
    static var frenchWeek: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "fr_FR")
        cal.firstWeekday = 2 // Monday
        cal.timeZone = TimeZone(identifier: "Europe/Paris") ?? .current
        return cal
    }

    /// Returns the first instant of the month containing `date`.
    func startOfMonth(for date: Date) -> Date {
        let components = dateComponents([.year, .month], from: date)
        return self.date(from: components) ?? date
    }

    /// Returns the last instant of the month containing `date`
    /// (start-of-next-month minus 1 second).
    func endOfMonth(for date: Date) -> Date? {
        guard let nextMonth = self.date(byAdding: .month, value: 1, to: date) else {
            return nil
        }
        let nextStart = startOfMonth(for: nextMonth)
        return self.date(byAdding: .second, value: -1, to: nextStart)
    }

    /// Returns the first instant of the week containing `date`
    /// (Monday 00:00 local).
    func startOfWeek(for date: Date) -> Date {
        let components = dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return self.date(from: components) ?? date
    }

    /// Returns the last instant of the week containing `date`
    /// (start-of-next-week minus 1 second).
    func endOfWeek(for date: Date) -> Date? {
        guard let nextWeek = self.date(byAdding: .weekOfYear, value: 1, to: date) else {
            return nil
        }
        let nextStart = startOfWeek(for: nextWeek)
        return self.date(byAdding: .second, value: -1, to: nextStart)
    }
}
