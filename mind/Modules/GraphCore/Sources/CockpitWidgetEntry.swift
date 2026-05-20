import Foundation

/// v1.0-alpha.16 — Pure data + formatter substrate behind the Cockpit
/// Lock Screen widget (the actual WidgetKit configuration + SwiftUI
/// view live in the `MINDWidgets` app-extension target).
///
/// The legacy v0.27.1 `LockScreenWidget` reads the obsolete second-
/// brain `Node` count; the cockpit pivot (v1.0-alpha.*) reframed MIND
/// as a Numelite Studio cockpit, so the Lock Screen surface needs to
/// mirror what HomeView actually shows — the new-lead inbox + portfolio
/// KPIs (active projects, MRR).
///
/// Same testability pattern as `LockScreenEntrySnapshot`: putting the
/// value type + the formatters here (not in the widget extension)
/// makes them exerciseable from `MINDTests` without forcing the test
/// target to import the WidgetKit extension (which is sandboxed away
/// from the host app's unit-test bundle).
///
/// The widget extension wraps `CockpitWidgetSnapshot` inside a
/// `TimelineEntry` because the WidgetKit timeline contract requires a
/// `date: Date` field. Tests only care about the count + MRR + last-
/// lead columns and the deterministic formatting branches, so the
/// snapshot ships those five columns + the matching helpers and
/// nothing else.
public struct CockpitWidgetSnapshot: Sendable, Equatable {
    /// Wall-clock time the snapshot was minted. The widget surface
    /// reads this so future tone shifts (morning / afternoon / evening)
    /// can ride the same field. Tests pin it through the explicit
    /// constructor argument so the boundary stays deterministic.
    public let date: Date

    /// Count of `Lead` rows with `status == "new"` — what HomeView's
    /// "Aujourd'hui" inbox card surfaces at the top of the screen.
    /// Clamped at 99 by the formatter so the accessory family budgets
    /// never overflow.
    public let newLeadCount: Int

    /// Count of `Project` rows in `.active` or `.maintenance` lifecycle
    /// stages — mirrors the `activeProjects` filter HomeView's portfolio
    /// carousel renders.
    public let activeProjectsCount: Int

    /// Sum of `monthlyRecurringRevenueEUR` across every active /
    /// maintenance project, in euros. Drives the rectangular family's
    /// secondary line ("3 200 € MRR"). The portfolio KPI surface uses
    /// the same total.
    public let totalMRR_EUR: Int

    /// Most recently received `Lead`'s contact name (sorted by
    /// `receivedAt` desc), nil when the inbox is empty. The widget's
    /// rectangular body uses this for an at-a-glance "who just wrote
    /// in?" prompt.
    public let lastLeadContactName: String?

    /// Project name the most-recent lead routed to, nil when the lead's
    /// project is unresolved or the inbox is empty. Pairs with
    /// `lastLeadContactName` on the rectangular family's body line.
    public let lastLeadProjectName: String?

    public init(
        date: Date,
        newLeadCount: Int,
        activeProjectsCount: Int,
        totalMRR_EUR: Int,
        lastLeadContactName: String?,
        lastLeadProjectName: String?
    ) {
        self.date = date
        self.newLeadCount = newLeadCount
        self.activeProjectsCount = activeProjectsCount
        self.totalMRR_EUR = totalMRR_EUR
        self.lastLeadContactName = lastLeadContactName
        self.lastLeadProjectName = lastLeadProjectName
    }

    /// Pre-baked sample for previews + the widget's `placeholder(in:)`.
    /// Not consumed by tests directly (they pass explicit snapshots)
    /// but kept here so the widget extension and the test target share
    /// the same canonical "looks alive" preset.
    public static let placeholder = CockpitWidgetSnapshot(
        date: Date(timeIntervalSince1970: 0),
        newLeadCount: 3,
        activeProjectsCount: 6,
        totalMRR_EUR: 3_200,
        lastLeadContactName: "Sara",
        lastLeadProjectName: "IEF & Co"
    )

    /// Empty-inbox fallback the provider falls back to when the
    /// SwiftData fetch returns zero leads. The widget's rectangular
    /// family routes this through the "Aucun nouveau lead" CTA.
    public static let empty = CockpitWidgetSnapshot(
        date: Date(timeIntervalSince1970: 0),
        newLeadCount: 0,
        activeProjectsCount: 0,
        totalMRR_EUR: 0,
        lastLeadContactName: nil,
        lastLeadProjectName: nil
    )
}

/// v1.0-alpha.16 — Pure formatters used by both Cockpit Lock Screen
/// accessory families. Lives here (not in the widget target) so unit
/// tests can pin the boundaries without linking WidgetKit + AppIntents
/// (the widget extension's required toolchain isn't reachable from
/// the iOS unit-test target).
public enum CockpitWidgetFormatter {
    /// Clamps `newLeadCount` at 99 so the accessory inline family
    /// never blows the single-line budget on the Lock Screen. The
    /// widget extension calls this for every family — same source of
    /// truth shared by the test target.
    public static func formatLeadCount(_ count: Int) -> String {
        if count > 99 {
            return "99+"
        }
        if count < 0 {
            return "0"
        }
        return "\(count)"
    }

    /// MRR formatter. Renders the integer euro amount with a non-
    /// breaking-space thousand separator (`3 200 €`) — same shape as
    /// the HomeView KPI bar so the surfaces stay coherent. Returns
    /// "0 €" on negative or zero input.
    public static func formatMRR(_ amount: Int) -> String {
        let clamped = max(0, amount)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        // Non-breaking space — matches the French-locale typography
        // convention used across the cockpit UI (avoids the thousand
        // separator wrapping to a new line inside a narrow widget).
        formatter.groupingSeparator = "\u{00A0}"
        formatter.usesGroupingSeparator = true
        let body = formatter.string(from: NSNumber(value: clamped)) ?? "\(clamped)"
        return "\(body)\u{00A0}€"
    }

    /// Rectangular header — the first line of the `.accessoryRectangular`
    /// family. Pluralisation matches the iOS HIG (1 lead / N leads /
    /// 99+ leads); the empty state surfaces the "Aucun lead" idle copy
    /// that pairs with the body fallback line.
    public static func rectangularHeader(for snapshot: CockpitWidgetSnapshot) -> String {
        switch snapshot.newLeadCount {
        case 0: return "Aucun nouveau lead"
        case 1: return "1 nouveau lead"
        default: return "\(formatLeadCount(snapshot.newLeadCount)) nouveaux leads"
        }
    }

    /// Rectangular body — the second (and optional third) line of the
    /// `.accessoryRectangular` family. Three branches:
    ///   - Both contact + project known → "Sara · IEF & Co"
    ///   - Only contact known           → "Sara"
    ///   - Empty inbox                  → MRR summary fallback so the
    ///     widget still carries actionable info on the idle day.
    public static func rectangularBody(for snapshot: CockpitWidgetSnapshot) -> String {
        if let name = snapshot.lastLeadContactName, !name.isEmpty {
            if let project = snapshot.lastLeadProjectName, !project.isEmpty {
                return "\(name) · \(project)"
            }
            return name
        }
        // Empty inbox — fall back to the portfolio MRR summary so the
        // surface stays useful when nothing new came in.
        return "\(formatMRR(snapshot.totalMRR_EUR)) MRR"
    }

    /// Inline complication body — single line shown next to the date
    /// on the Lock Screen. Always carries the brand-prefixed lead
    /// count so the reader knows which app the row belongs to.
    public static func inlineBody(for snapshot: CockpitWidgetSnapshot) -> String {
        if snapshot.newLeadCount == 1 {
            return "MIND · 1 lead"
        }
        return "MIND · \(formatLeadCount(snapshot.newLeadCount)) leads"
    }

    /// Deep-link URL the widget's `widgetURL(...)` opens when the user
    /// taps the complication. The host App parses `mind://leads` and
    /// routes to the Home tab's lead inbox card. Kept static so the
    /// URL string never drifts between the widget extension and the
    /// test target.
    public static let deepLinkURL = URL(string: "mind://leads")!
}
