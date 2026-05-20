import Foundation

/// v1.0-alpha.13 — Pure dormant-project detection.
///
/// On every app foreground MIND surfaces a "X projets dormants —
/// archiver ?" card on HomeView. The heuristic looks at three
/// signals per active project:
///
/// 1. `lastActivityAt` — the SwiftData column already touched on
///    every audit / lead / manual edit. Older than `thresholdDays`
///    is the **headline** dormancy signal.
/// 2. Most-recent `Lead.receivedAt` linked through `project.leads`.
///    A lead landing in the last 90 days keeps the project alive
///    even when no audit has run.
/// 3. Cached GitHub `lastPushByRepo` keyed by `githubRepo` string.
///    A push in the window keeps a project active when MIND just
///    hasn't seen it run an audit lately.
///
/// **Dormant ≡ all three signals are stale.** The heuristic is
/// deliberately conservative — a single fresh signal (one lead, one
/// commit, one audit) keeps the project active. The whole point of
/// the suggestion is that Mehdi never sees a "Archive this?" card
/// for a project that's actually billing or being shipped.
///
/// Lives in GraphCore so the tests exercise it against real
/// `Project` rows without dragging in SwiftUI / SwiftData fetches.
public enum ProjectLifecycleHeuristic {
    /// Default look-back window for the dormant heuristic. 90 days
    /// matches Mehdi's quarterly billing rhythm — a project that
    /// hasn't shown a lead, commit, or audit in 90 days isn't paying
    /// rent.
    public static let defaultThresholdDays: Int = 90

    /// Filter the input array to the dormant slice. Excludes
    /// archived projects entirely (they're already in the tombstone
    /// state). Returns the dormant projects ordered longest-dormant
    /// first so the HomeView card surfaces the most-stale row at the
    /// top of its list.
    public static func dormantProjects(
        _ projects: [Project],
        lastPushByRepo: [String: Date] = [:],
        thresholdDays: Int = defaultThresholdDays,
        asOf: Date = .now
    ) -> [Project] {
        let clampedDays = max(1, thresholdDays)
        let cutoff = Calendar.gregorian.date(
            byAdding: .day,
            value: -clampedDays,
            to: asOf
        ) ?? asOf
        return projects
            .filter { project in
                project.lifecycleStageEnum != .archived &&
                isDormant(
                    project,
                    cutoff: cutoff,
                    lastPushByRepo: lastPushByRepo
                )
            }
            .sorted { lhs, rhs in
                lhs.lastActivityAt < rhs.lastActivityAt
            }
    }

    /// Human-readable reason string for the card row. Picks the
    /// **least** stale signal so the explanation matches the user's
    /// mental model: "tu n'as pas touché ce projet depuis X". When
    /// every signal is missing, falls back to a generic "no
    /// activity" line so the row never lands without an explanation.
    public static func reason(
        for project: Project,
        lastPush: Date?,
        asOf: Date = .now
    ) -> String {
        let calendar = Calendar.gregorian
        let activityDays = daysBetween(project.lastActivityAt, and: asOf, calendar: calendar)
        let pushDays = lastPush.map {
            daysBetween($0, and: asOf, calendar: calendar)
        }
        let leadDays = mostRecentLeadDate(in: project).map {
            daysBetween($0, and: asOf, calendar: calendar)
        }

        // Pick the youngest signal — the one whose stale window is
        // smallest. Tie-break order: lead > push > activity.
        var candidates: [(label: ReasonBranch, days: Int)] = [
            (.activity, activityDays)
        ]
        if let pushDays {
            candidates.append((.push, pushDays))
        }
        if let leadDays {
            candidates.append((.lead, leadDays))
        }
        let pick = candidates.min(by: { $0.days < $1.days }) ?? candidates[0]

        switch pick.label {
        case .lead:
            let format = String(localized: "home.dormant.reason.noLead")
            return String(format: format, pick.days)
        case .push:
            let format = String(localized: "home.dormant.reason.noPush")
            return String(format: format, pick.days)
        case .activity:
            if activityDays == 0 {
                return String(localized: "home.dormant.reason.noActivity")
            }
            let format = String(localized: "home.dormant.reason.noAudit")
            return String(format: format, pick.days)
        }
    }

    // MARK: - Private

    /// Whether a single project is dormant relative to a cutoff. A
    /// fresh signal on **any** axis (activity, lead, push) keeps it
    /// active.
    private static func isDormant(
        _ project: Project,
        cutoff: Date,
        lastPushByRepo: [String: Date]
    ) -> Bool {
        // Axis 1: last activity (audits, manual edits, etc.).
        if project.lastActivityAt > cutoff { return false }
        // Axis 2: a lead landing inside the window.
        if let mostRecent = mostRecentLeadDate(in: project),
           mostRecent > cutoff {
            return false
        }
        // Axis 3: GitHub push inside the window.
        if let repo = project.githubRepo,
           let lastPush = lastPushByRepo[repo],
           lastPush > cutoff {
            return false
        }
        return true
    }

    /// Most-recent lead receipt timestamp for a project, or nil when
    /// the project has no leads (or the SwiftData relationship hasn't
    /// hydrated yet). Reading `.leads` from outside a MainActor would
    /// trip the schema; the heuristic itself runs from the home view
    /// which is already MainActor-bound.
    private static func mostRecentLeadDate(in project: Project) -> Date? {
        guard let leads = project.leads, !leads.isEmpty else { return nil }
        return leads.map(\.receivedAt).max()
    }

    /// Floor of the day difference between two dates. Negative
    /// inputs clamp to 0 so the formatter never produces "-3 jours".
    private static func daysBetween(
        _ start: Date,
        and end: Date,
        calendar: Calendar
    ) -> Int {
        let interval = end.timeIntervalSince(start)
        guard interval > 0 else { return 0 }
        return max(0, Int(interval / 86_400))
    }

    /// Internal switch for `reason(for:)`. Mirrors the three
    /// localized reason variants so the dormant card can colour the
    /// chip per branch in a future polish.
    public enum ReasonBranch: Sendable, Equatable {
        case lead
        case push
        case activity
    }
}

// MARK: - Calendar helper

private extension Calendar {
    /// Plain Gregorian calendar pinned to the current time zone.
    /// Project lifecycle math doesn't need French week-start
    /// gymnastics — it counts whole days.
    static var gregorian: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Paris") ?? .current
        return cal
    }
}
