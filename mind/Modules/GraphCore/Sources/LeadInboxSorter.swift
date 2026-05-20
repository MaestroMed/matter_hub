import Foundation

/// v1.0-alpha.3 — Pure namespace that sorts `[Lead]` for the
/// "Aujourd'hui" HomeView inbox + the per-Project LeadsList sheet.
///
/// Lives in `GraphCore` (not the app target) so the sort can be unit-
/// tested against the SwiftData `@Model` without spinning up a
/// `ModelContainer`. The function is `static` + pure: same inputs →
/// same output, zero side effects, no SwiftData fetches, no
/// `@MainActor` dance.
///
/// Two sort keys cover every surface the Cockpit ships today:
/// - `.dateDescending` — drives the HomeView "Aujourd'hui" inbox
///   (newest leads float to the top, matching the "what just came
///   in?" mental model).
/// - `.statusPriority` — drives the qualification triage view: `.new`
///   first (Mehdi hasn't touched them), then `.qualified` (already
///   triaged worth pursuing), then `.contacted` (already replied),
///   then `.won` / `.lost` / `.spam` (terminal).
///
/// Stable + deterministic — `statusPriority` ties break on
/// `receivedAt` descending so two `.new` leads from the same minute
/// retain the same order across renders, never flicker.
public enum LeadInboxSorter {
    /// Sort keys exposed by the inbox UI. Stable rawValue strings so
    /// future telemetry breadcrumbs can ride the same identifier
    /// without translating an enum case.
    public enum SortKey: String, Sendable, CaseIterable, Equatable {
        case dateDescending
        case statusPriority
    }

    /// Sort a Lead array per the requested key. Returns a new array
    /// — caller-owned, immutable, safe to feed straight into a
    /// SwiftUI `ForEach`. The empty + single-element paths short-
    /// circuit so we don't allocate a sorter for the zero/one case.
    public static func sort(_ leads: [Lead], by key: SortKey) -> [Lead] {
        guard leads.count > 1 else { return leads }
        switch key {
        case .dateDescending:
            return leads.sorted { $0.receivedAt > $1.receivedAt }
        case .statusPriority:
            return leads.sorted { lhs, rhs in
                let lp = priority(of: lhs.statusEnum)
                let rp = priority(of: rhs.statusEnum)
                if lp != rp { return lp < rp }
                // Tie-breaker: newest first inside a status bucket.
                return lhs.receivedAt > rhs.receivedAt
            }
        }
    }

    /// Lower number = surfaces first. Drives the documented order
    /// `.new` → `.qualified` → `.contacted` → `.won` → `.lost`
    /// → `.spam`. Exposed `public` so the UI can read the same
    /// priorities for badge ordering without re-implementing the
    /// table.
    public static func priority(of status: LeadStatus) -> Int {
        switch status {
        case .new:        return 0
        case .qualified:  return 1
        case .contacted:  return 2
        case .won:        return 3
        case .lost:       return 4
        case .spam:       return 5
        }
    }
}
