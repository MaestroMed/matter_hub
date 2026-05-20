import Foundation

/// v1.0-alpha.3 — Pure namespace sorting `[Project]` for the new
/// ProjectsView. Three keys cover the cockpit surface:
/// - `.activityDescending` — recently-touched projects float to the
///   top (default, matches "what's hot?" mental model).
/// - `.mrrDescending` — biggest retainers float to the top
///   (revenue triage when planning the week).
/// - `.alphabetical` — locale-aware FR comparison so "Épée" sorts
///   alongside "Epee" and not at the end of the list.
///
/// Archived projects always sort to the bottom regardless of key,
/// per the Cockpit "active first" convention. Inside the archived
/// bucket the chosen key still applies — so two archived projects
/// sort by MRR / activity / alpha the same way two active ones do.
///
/// Lives in GraphCore so tests can exercise the function against
/// real `Project` rows without dragging in SwiftUI.
public enum ProjectSorter {
    public enum SortKey: String, Sendable, CaseIterable, Equatable {
        case activityDescending
        case mrrDescending
        case alphabetical
    }

    /// Sort a Project array. Empty + single-element paths short-
    /// circuit. Archived projects always group at the bottom.
    public static func sort(_ projects: [Project], by key: SortKey) -> [Project] {
        guard projects.count > 1 else { return projects }
        let collation: (Project, Project) -> Bool
        switch key {
        case .activityDescending:
            collation = { $0.lastActivityAt > $1.lastActivityAt }
        case .mrrDescending:
            collation = { $0.monthlyRecurringRevenueEUR > $1.monthlyRecurringRevenueEUR }
        case .alphabetical:
            collation = {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
        return projects.sorted { lhs, rhs in
            let lhsArchived = lhs.lifecycleStageEnum == .archived
            let rhsArchived = rhs.lifecycleStageEnum == .archived
            if lhsArchived != rhsArchived { return !lhsArchived }
            return collation(lhs, rhs)
        }
    }

    /// Pure search filter — case-insensitive substring match against
    /// `name` and `host`. Empty needle returns the unfiltered input.
    public static func filter(_ projects: [Project], query: String) -> [Project] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return projects }
        return projects.filter { project in
            project.name.lowercased().contains(needle) ||
            project.host.lowercased().contains(needle)
        }
    }
}
