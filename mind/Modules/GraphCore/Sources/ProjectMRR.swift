import Foundation

/// v1.0-alpha.3 — Pure helpers for the per-Project + per-portfolio
/// MRR math the Cockpit surfaces.
///
/// - `total(of:)` sums the MRR of every active retainer project.
///   Oneshot rows + non-active retainers are excluded — a discovery
///   retainer doesn't bill yet, an archived retainer stopped billing.
/// - `formatEUR(_:)` formats an integer euro amount as `€X/mo` (FR
///   locale convention — the slash form Mehdi already uses in his
///   public CV).
public enum ProjectMRR {
    /// Sum of monthly recurring revenue across the active retainer
    /// rows in `projects`. Empty array returns 0. Returns Int because
    /// the source field is Int.
    public static func total(of projects: [Project]) -> Int {
        projects.reduce(0) { acc, project in
            guard project.contractTypeEnum == .retainer else { return acc }
            guard
                project.lifecycleStageEnum == .active ||
                project.lifecycleStageEnum == .maintenance
            else { return acc }
            return acc + max(0, project.monthlyRecurringRevenueEUR)
        }
    }

    /// Format a euro amount as `€<amount>/mo`. `0` → `€0/mo` (kept
    /// uniform — no special-case so the caller can always rely on
    /// the same shape). FR locale separators (1 000) but the unit
    /// label stays compact for the iPhone card real estate.
    public static func formatEUR(_ amount: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.maximumFractionDigits = 0
        let number = formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
        return "€\(number)/mo"
    }

    /// Count the active retainer rows. Surfaced in the HomeView
    /// subtitle ("X leads · Y projets actifs · €Z/mois").
    public static func activeRetainerCount(in projects: [Project]) -> Int {
        projects.filter { project in
            project.contractTypeEnum == .retainer &&
            (project.lifecycleStageEnum == .active ||
             project.lifecycleStageEnum == .maintenance)
        }.count
    }

    /// Count every active or maintenance project (retainer or
    /// oneshot). Surfaced alongside the MRR pill on the HomeView
    /// greeting subtitle.
    public static func activeCount(in projects: [Project]) -> Int {
        projects.filter { project in
            project.lifecycleStageEnum == .active ||
            project.lifecycleStageEnum == .maintenance
        }.count
    }
}
