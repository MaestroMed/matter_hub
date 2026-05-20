import Foundation

/// v1.0-alpha.17 — Pure formatters the Watch UI calls without ever
/// touching `WCSession`, `UserDefaults`, or `Locale`. Locked by
/// `WatchSnapshotFormatterTests` so the visual output is identical on
/// the simulator and on the device.
public enum WatchKPIFormatter {

    /// Compact monthly recurring revenue glyph the Watch displays
    /// next to the EUR pill. Mirrors the iOS 26 widget formatter
    /// (`WidgetMRRFormatter.compact`) but renders without the suffix
    /// for the >= 1k case so the 38mm watch face still fits the row.
    ///
    /// - <1000: "830€"
    /// - 1000..9999: "1.2k€" (one decimal, drops .0 for round)
    /// - 10000..999999: "12k€"
    /// - >=1000000: "1M€"
    /// - 0/negative: "0€"
    public static func compactEUR(_ amount: Int) -> String {
        if amount <= 0 { return "0€" }
        if amount < 1_000 { return "\(amount)€" }
        if amount < 10_000 {
            let value = Double(amount) / 1_000.0
            let rounded = (value * 10).rounded() / 10
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

    /// Compact lead-count label rendered above the "leads aujourd'hui"
    /// row. Caps the display at 99+ so a long-tail spike never breaks
    /// the 1-line layout on the 38mm watch face.
    public static func leadCount(_ count: Int) -> String {
        if count <= 0 { return "0" }
        if count > 99 { return "99+" }
        return String(count)
    }

    /// Renders a transcript preview shown on the lead row. Collapses
    /// whitespace, trims, then clips to `maxPreviewLength` with a
    /// trailing ellipsis.
    public static let maxPreviewLength = 60

    public static func preview(_ message: String) -> String {
        let trimmed = message
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if trimmed.isEmpty { return "" }
        if trimmed.count <= maxPreviewLength { return trimmed }
        return "\(trimmed.prefix(maxPreviewLength))\u{2026}"
    }

    /// Formats elapsed Focus seconds as "MM:SS" / "H:MM:SS". Never
    /// returns a negative duration — the Watch UI clamps the user-
    /// facing label at 00:00.
    public static func elapsed(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        let hours = clamped / 3_600
        let minutes = (clamped % 3_600) / 60
        let secs = clamped % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    /// Compact error-count badge for the deployment row. >= 99 caps
    /// out at "99+" so the 1-line glyph never wraps. 0 still returns
    /// "0" (the UI displays "OK" when count == 0 via a separate
    /// branch, this helper only handles the digit shape).
    public static func errorCount(_ count: Int) -> String {
        if count <= 0 { return "0" }
        if count > 99 { return "99+" }
        return String(count)
    }
}
