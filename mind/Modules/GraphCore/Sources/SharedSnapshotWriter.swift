import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// v1.0-alpha.16 — Cross-process bridge that lets the host iOS App
/// hand a fresh portfolio + lead-inbox snapshot to the `MINDWidgets`
/// app-extension target without going through SwiftData's CloudKit
/// mirror (which is async and not reachable from a widget timeline
/// provider in any deterministic way).
///
/// The host app calls `refresh(...)` on every `.active` scene phase
/// after computing the same numbers HomeView's KPI bar already
/// shows. We persist them into the shared App Group
/// `UserDefaults(suiteName: "group.app.mind.ios")` under the four
/// `mind.shared.*` keys, then nudge WidgetKit to reload every active
/// timeline via `WidgetCenter.shared.reloadAllTimelines()` so the
/// iOS 26 Lock Screen widgets pick up the latest values before the
/// user looks at their device.
///
/// Why an enum, not an actor: the entire surface is synchronous IO
/// on `UserDefaults`, the WidgetCenter call is `nonisolated`, and
/// the host always calls us on the MainActor (scenePhase reads sit
/// on the MainActor by SwiftUI contract). Wrapping everything in an
/// actor would force every caller through an `await` for zero
/// benefit. Static methods on a `@MainActor` enum keep the call
/// sites trivial.
///
/// All `reloadAllTimelines()` calls are wrapped in
/// `#if canImport(WidgetKit)` so Mac Catalyst builds (no WidgetKit
/// reach) compile cleanly — Catalyst is iOS-26-flagged through the
/// App target but it doesn't ship the widget extension; the
/// dock-badge path in MINDApp already covers that surface.
///
/// Nonisolated by design — UserDefaults is thread-safe, WidgetCenter
/// is nonisolated, and the widget extension's timeline provider can't
/// hop onto the MainActor for the synchronous `readSnapshot()` call
/// without a Task indirection. Host-side callers can still safely
/// invoke us from the MainActor; the writes/reads are race-free as
/// long as the host's scene-phase observer is the sole writer
/// (UserDefaults coalesces concurrent writes itself).
public enum SharedSnapshotWriter {

    // MARK: - Keys

    /// App Group identifier. Lives in `GraphContainer.appGroupIdentifier`
    /// too; duplicated here only because making this enum reach into
    /// `GraphContainer` would force the widget extension to link
    /// CloudKit (which it can't). String constants are cheap.
    public static let suiteName = "group.app.mind.ios"

    /// `Int`. Total count of `Lead` rows with `status == "new"` at the
    /// moment of the last `refresh(...)` call. Negative inputs are
    /// clamped to 0 — the widget surface treats 0 as "no leads
    /// today" and renders the empty-state CTA.
    public static let keyLeadCount = "mind.shared.leadCount"

    /// `String`. Most-recent lead's `contactName`, truncated to 20
    /// chars + ellipsis if it overflows. Empty string when the
    /// caller passes nil or an empty contact name — the widget's
    /// rectangular family interprets empty as "no recent contact".
    public static let keyLeadLastContact = "mind.shared.leadLastContact"

    /// `Int`. Sum of monthly recurring revenue across every active
    /// retainer project, computed by `ProjectMRR.total(of:)` on the
    /// host side. Negative inputs are clamped to 0.
    public static let keyTotalMRR = "mind.shared.totalMRR"

    /// `String`. Name of the project whose latest Vercel deployment
    /// is in the `ERROR` state. Nil collapses to empty string on
    /// write so the widget's accessory-inline branch can treat the
    /// empty case as "every project is green" without juggling a
    /// String? from UserDefaults.
    public static let keyCriticalProjectName = "mind.shared.criticalProjectName"

    // MARK: - Truncation

    /// 20-char truncation budget the rectangular accessory family
    /// expects. The accessory chrome on iPhone 17 Pro fits roughly
    /// 24 monospaced glyphs before the rest of the row clips; 20 +
    /// an ellipsis keeps a safety margin for accent-heavy French
    /// names (`Élisabeth-Antoinette`).
    public static let maxContactLength = 20

    // MARK: - Public API

    /// Persists the four widget-visible columns into the App Group
    /// suite, then asks WidgetKit to reload every active timeline.
    ///
    /// - parameter leadCount: count of leads with `status == "new"`.
    ///   Clamped at 0 on the floor side; no ceiling clamp (the widget
    ///   handles the >999 case via `LockScreenWidgetFormatter`).
    /// - parameter leadLastContact: contactName of the most-recent
    ///   lead (sorted by `receivedAt` desc). Nil + empty string both
    ///   collapse to "" on write. Names longer than `maxContactLength`
    ///   get truncated with a trailing ellipsis.
    /// - parameter totalMRR: portfolio MRR in EUR. Clamped at 0.
    /// - parameter criticalProjectName: name of the project whose
    ///   latest deployment is `ERROR`. Pass nil when every project
    ///   is green; nil + empty string both write "".
    public static func refresh(
        leadCount: Int,
        leadLastContact: String?,
        totalMRR: Int,
        criticalProjectName: String?
    ) {
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let clampedLeadCount = max(0, leadCount)
        let truncatedContact = truncate(leadLastContact)
        let clampedMRR = max(0, totalMRR)
        let projectName = criticalProjectName?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        defaults.set(clampedLeadCount, forKey: keyLeadCount)
        defaults.set(truncatedContact, forKey: keyLeadLastContact)
        defaults.set(clampedMRR, forKey: keyTotalMRR)
        defaults.set(projectName, forKey: keyCriticalProjectName)

        reloadTimelines()
    }

    /// Clears every widget-visible column. Used by Settings → Danger
    /// Zone's "Wipe all data" flow so a stale snapshot never lingers
    /// in the App Group suite after a graph reset.
    public static func clear() {
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removeObject(forKey: keyLeadCount)
        defaults.removeObject(forKey: keyLeadLastContact)
        defaults.removeObject(forKey: keyTotalMRR)
        defaults.removeObject(forKey: keyCriticalProjectName)
        reloadTimelines()
    }

    /// Reads the cached snapshot back out. The widget extension's
    /// timeline providers call this in `fetchEntry()`; the host app
    /// never needs to (it owns the source data already).
    ///
    /// `nonisolated` so timeline providers (which can't trivially
    /// hop to the MainActor inside `getTimeline`'s closure shape)
    /// can read the snapshot without going through an `await`.
    /// UserDefaults reads are thread-safe by Apple contract.
    public nonisolated static func readSnapshot(
        suiteName: String = SharedSnapshotWriter.suiteName
    ) -> SharedSnapshot {
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let leadCount = max(0, defaults.integer(forKey: keyLeadCount))
        let rawContact = defaults.string(forKey: keyLeadLastContact) ?? ""
        let lastContact: String? = rawContact.isEmpty ? nil : rawContact
        let mrr = max(0, defaults.integer(forKey: keyTotalMRR))
        let rawProject = defaults.string(forKey: keyCriticalProjectName) ?? ""
        let criticalProject: String? = rawProject.isEmpty ? nil : rawProject
        return SharedSnapshot(
            leadCount: leadCount,
            leadLastContact: lastContact,
            totalMRR: mrr,
            criticalProjectName: criticalProject
        )
    }

    // MARK: - Test seam

    /// Writes the four columns to an arbitrary suite. The production
    /// `refresh(...)` always targets `suiteName`; tests pin the
    /// suite to a hermetic one (`mind.tests.<UUID>`) so the
    /// round-trip + clamp logic stays exercised without polluting
    /// the real App Group container.
    public static func write(
        leadCount: Int,
        leadLastContact: String?,
        totalMRR: Int,
        criticalProjectName: String?,
        to suiteName: String
    ) {
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.set(max(0, leadCount), forKey: keyLeadCount)
        defaults.set(truncate(leadLastContact), forKey: keyLeadLastContact)
        defaults.set(max(0, totalMRR), forKey: keyTotalMRR)
        let projectName = criticalProjectName?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        defaults.set(projectName, forKey: keyCriticalProjectName)
    }

    /// Wipes the four columns from an arbitrary suite. Mirrors
    /// `clear()` but parameterised for tests.
    public static func clear(suiteName: String) {
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removeObject(forKey: keyLeadCount)
        defaults.removeObject(forKey: keyLeadLastContact)
        defaults.removeObject(forKey: keyTotalMRR)
        defaults.removeObject(forKey: keyCriticalProjectName)
    }

    // MARK: - Helpers

    /// Truncate a contact name to `maxContactLength` chars +
    /// trailing ellipsis. Nil + empty + whitespace-only collapse to
    /// "" so the on-disk shape stays canonical. Pure on Strings, no
    /// locale dependence — the rectangular accessory family already
    /// renders with `.lineLimit(1)`, this is a safety net on top.
    public static func truncate(_ contact: String?) -> String {
        guard let contact else { return "" }
        let trimmed = contact.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        if trimmed.count <= maxContactLength { return trimmed }
        let prefix = trimmed.prefix(maxContactLength)
        return "\(prefix)\u{2026}"
    }

    /// WidgetKit reload nudge. No-op on platforms that can't import
    /// WidgetKit (Mac Catalyst is iOS-26-flagged so this path
    /// compiles but won't actually reach a live extension on Mac).
    private static func reloadTimelines() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}

// MARK: - Read-side value type

/// v1.0-alpha.16 — Decoded shape the widget timeline providers reach
/// for. Pure value type so unit tests can pin every combination of
/// fields without touching the App Group container or WidgetKit
/// itself.
public struct SharedSnapshot: Sendable, Equatable {
    public let leadCount: Int
    public let leadLastContact: String?
    public let totalMRR: Int
    public let criticalProjectName: String?

    public init(
        leadCount: Int,
        leadLastContact: String?,
        totalMRR: Int,
        criticalProjectName: String?
    ) {
        self.leadCount = leadCount
        self.leadLastContact = leadLastContact
        self.totalMRR = totalMRR
        self.criticalProjectName = criticalProjectName
    }

    /// Empty default the widget falls back to when the App Group
    /// container is empty (first launch, post-wipe, fresh install
    /// where the host hasn't refreshed yet).
    public static let empty = SharedSnapshot(
        leadCount: 0,
        leadLastContact: nil,
        totalMRR: 0,
        criticalProjectName: nil
    )

    /// Pre-baked placeholder shown in WidgetKit's `placeholder(in:)`
    /// path while the timeline assembles. Matches the visual scale
    /// the production snapshot lands at for Mehdi's actual portfolio.
    public static let placeholder = SharedSnapshot(
        leadCount: 3,
        leadLastContact: "Karim Benali",
        totalMRR: 830,
        criticalProjectName: nil
    )
}

// MARK: - Pure formatters

/// v1.0-alpha.16 — Compact EUR formatter the circular Lock Screen
/// widget uses for the MRR pill ("830€", "1.2k€", "12k€"). Lives in
/// GraphCore so unit tests can pin every boundary without linking
/// WidgetKit.
public enum WidgetMRRFormatter {

    /// Format an integer euro amount as a compact accessory glyph.
    /// - <1000: raw count + €  (e.g. "830€")
    /// - 1000..9999: one decimal k€ (e.g. "1.2k€")
    /// - 10000..999999: integer k€ (e.g. "12k€")
    /// - >=1000000: integer M€ (e.g. "1M€")
    /// Negative inputs collapse to "0€".
    public static func compact(_ amount: Int) -> String {
        if amount <= 0 { return "0€" }
        if amount < 1_000 { return "\(amount)€" }
        if amount < 10_000 {
            let value = Double(amount) / 1_000.0
            let rounded = (value * 10).rounded() / 10
            // Drop the .0 suffix for round numbers ("1.0k€" -> "1k€").
            if rounded.truncatingRemainder(dividingBy: 1) == 0 {
                return "\(Int(rounded))k€"
            }
            return String(format: "%.1fk€", rounded)
        }
        if amount < 1_000_000 {
            return "\(amount / 1_000)k€"
        }
        return "\(amount / 1_000_000)M€"
    }
}

/// v1.0-alpha.16 — Inline deployment-status formatter. The
/// `.accessoryInline` family on iOS 26 supports up to ~36 monospaced
/// glyphs next to the Lock Screen clock. The formatter clips a long
/// project name to 24 chars so the symbol + name + status mark fit
/// comfortably inside that budget.
public enum WidgetDeploymentFormatter {

    /// Maximum project-name length surfaced inline. Anything longer
    /// is truncated with an ellipsis so the inline glyph stays
    /// readable.
    public static let maxProjectLength = 24

    /// `criticalProjectName == nil` -> "All projects healthy" line
    /// rendered with the green check. A non-nil name surfaces the
    /// "<Name> error" line with the warning glyph.
    /// `defaultProjectName` falls in when every project is fine but
    /// the host still wants to surface a brand-prefixed status row.
    public static func inlineLine(
        criticalProjectName: String?,
        defaultProjectName: String
    ) -> String {
        if let critical = criticalProjectName?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !critical.isEmpty
        {
            let clipped = clip(critical)
            return "\(clipped) \u{26A0}\u{FE0F}"
        }
        let fallback = clip(defaultProjectName)
        return "\(fallback) \u{2713}"
    }

    /// Clip helper — never split on a grapheme; trailing ellipsis on
    /// overflow.
    public static func clip(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= maxProjectLength { return trimmed }
        return "\(trimmed.prefix(maxProjectLength))\u{2026}"
    }
}
