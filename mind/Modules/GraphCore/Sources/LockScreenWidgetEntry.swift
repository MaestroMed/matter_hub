import Foundation

/// v0.27.1 — Pure data + formatter substrate behind the Lock Screen
/// widget (the actual WidgetKit configuration + SwiftUI view live in
/// the `MINDWidgets` app-extension target). Putting the value type +
/// the two formatters here makes them testable from `MINDTests`
/// without forcing the test target to import the widget extension
/// (which is sandboxed away from the host app's unit-test bundle).
///
/// The widget extension wraps `LockScreenEntrySnapshot` inside a
/// `TimelineEntry` because the WidgetKit timeline contract requires
/// a `date: Date` field. Tests only care about the count + lastTitle
/// columns and the deterministic formatting branches, so the
/// snapshot ships those three columns + the matching helpers and
/// nothing else.
public struct LockScreenEntrySnapshot: Sendable, Equatable {
    /// Wall-clock time the snapshot was minted. The widget surface
    /// reads this so the rectangular complication can drift its
    /// rendering tone between morning + afternoon + evening (future
    /// iteration). Tests pin it through the explicit constructor
    /// argument so the boundary stays deterministic.
    public let date: Date
    /// Combined `note + capture` Node count rendered as the circular
    /// dial's centre number + the inline complication's summary. The
    /// formatter below clamps anything above 999 to `999+` so the
    /// system's 3-glyph budget never overflows.
    public let totalCount: Int
    /// Most recent Node title (sorted by `updatedAt` desc), nil when
    /// the graph is empty. The rectangular complication falls back to
    /// a friendly "Tap to capture" CTA on nil.
    public let lastTitle: String?

    public init(date: Date, totalCount: Int, lastTitle: String?) {
        self.date = date
        self.totalCount = totalCount
        self.lastTitle = lastTitle
    }

    /// Pre-baked sample for previews + the widget's
    /// `placeholder(in:)`. Not consumed by tests directly — they pass
    /// explicit snapshots — but kept here so the widget extension and
    /// the test target share the same canonical "looks alive" preset.
    public static let placeholder = LockScreenEntrySnapshot(
        date: Date(timeIntervalSince1970: 0),
        totalCount: 42,
        lastTitle: "Spark from this morning"
    )

    /// Empty-graph fallback the provider falls back to when the
    /// SwiftData fetch returns zero `note` / `capture` Nodes. The
    /// widget's rectangular family routes this through the
    /// "Tap to capture" CTA branch.
    public static let empty = LockScreenEntrySnapshot(
        date: Date(timeIntervalSince1970: 0),
        totalCount: 0,
        lastTitle: nil
    )
}

/// v0.27.1 — Pure formatters used by all three accessory families.
/// Lives here (not in the widget target) so unit tests can pin the
/// boundaries without linking WidgetKit + AppIntents (the widget
/// extension's required toolchain isn't reachable from the iOS
/// unit-test target).
public enum LockScreenWidgetFormatter {
    /// Clamps `totalCount` at 999 so the circular dial never
    /// overflows the system's 3-glyph budget. The widget extension
    /// calls this for every accessory family — same source of truth
    /// shared by the test target.
    public static func formatCount(_ count: Int) -> String {
        if count > 999 {
            return "999+"
        }
        if count < 0 {
            return "0"
        }
        return "\(count)"
    }

    /// Rectangular-header builder. Returns the FR/EN-agnostic header
    /// the rectangular family renders above the latest thought title.
    /// Pluralisation matches the iOS HIG (1 thought / N thoughts);
    /// the empty-graph state surfaces the "Empty graph" CTA copy that
    /// pairs with the "Tap to capture" body line.
    public static func rectangularHeader(for snapshot: LockScreenEntrySnapshot) -> String {
        switch snapshot.totalCount {
        case 0: return "Empty graph"
        case 1: return "1 thought"
        default: return "\(formatCount(snapshot.totalCount)) thoughts"
        }
    }

    /// Inline complication body. Always prefixed by the brand label
    /// so a reader scanning the Lock Screen knows the row belongs to
    /// MIND. The font budget on `.accessoryInline` is one line of
    /// system text, so the formatter stays compact.
    public static func inlineBody(for snapshot: LockScreenEntrySnapshot) -> String {
        if snapshot.totalCount == 1 {
            return "MIND · 1 thought"
        }
        return "MIND · \(formatCount(snapshot.totalCount)) thoughts"
    }

    /// Deep-link URL the widget's `widgetURL(...)` opens when the user
    /// taps the complication. The host App parses
    /// `mind://lock` and routes to a "fresh capture" CTA on the Home
    /// tab (future iteration). Kept as a static so the URL string
    /// never drifts between the widget extension and the test target.
    public static let deepLinkURL = URL(string: "mind://lock")!
}
