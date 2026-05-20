import XCTest
@testable import GraphCore

/// v1.0-alpha.17 — Locks the pure `WatchKPIFormatter` the Apple Watch
/// UI calls on every wrist glance. The Watch target ships a thin
/// duplicate of the same shape (Watch/Sources/WatchKPIFormatter.swift)
/// so these tests double as the contract both targets follow.
final class WatchSnapshotFormatterTests: XCTestCase {

    // MARK: - compactEUR

    /// Negative and zero amounts collapse to "0€" so the row never
    /// renders a stray "-100€".
    func test_compactEUR_zeroAndNegativeCollapseToZero() {
        XCTAssertEqual(WatchKPIFormatter.compactEUR(0), "0€")
        XCTAssertEqual(WatchKPIFormatter.compactEUR(-1), "0€")
        XCTAssertEqual(WatchKPIFormatter.compactEUR(-9_999), "0€")
    }

    /// Amounts below 1k render as a raw count + €. Mehdi's current
    /// MRR (830€) is the canonical example for this branch.
    func test_compactEUR_under1k_rendersRawCount() {
        XCTAssertEqual(WatchKPIFormatter.compactEUR(1), "1€")
        XCTAssertEqual(WatchKPIFormatter.compactEUR(830), "830€")
        XCTAssertEqual(WatchKPIFormatter.compactEUR(999), "999€")
    }

    /// Amounts in [1k, 10k) render with one decimal place; round-
    /// number boundaries drop the .0 suffix so "1.0k€" -> "1k€".
    func test_compactEUR_thousandsRangeRendersDecimalKEur() {
        XCTAssertEqual(WatchKPIFormatter.compactEUR(1_000), "1k€")
        XCTAssertEqual(WatchKPIFormatter.compactEUR(1_200), "1.2k€")
        XCTAssertEqual(WatchKPIFormatter.compactEUR(4_500), "4.5k€")
        XCTAssertEqual(WatchKPIFormatter.compactEUR(9_999), "10k€")
    }

    /// Amounts in [10k, 1M) render as an integer k€. Mid-range
    /// portfolio (12k€, 250k€) is the typical example.
    func test_compactEUR_tenThousandsRangeRendersIntegerKEur() {
        XCTAssertEqual(WatchKPIFormatter.compactEUR(12_000), "12k€")
        XCTAssertEqual(WatchKPIFormatter.compactEUR(250_000), "250k€")
        XCTAssertEqual(WatchKPIFormatter.compactEUR(999_999), "999k€")
    }

    /// Amounts at or above 1M render as integer M€ glyphs.
    func test_compactEUR_millionsRangeRendersIntegerMEur() {
        XCTAssertEqual(WatchKPIFormatter.compactEUR(1_000_000), "1M€")
        XCTAssertEqual(WatchKPIFormatter.compactEUR(2_500_000), "2M€")
    }

    // MARK: - leadCount

    /// 0 and negative inputs collapse to "0".
    func test_leadCount_clampsAtZero() {
        XCTAssertEqual(WatchKPIFormatter.leadCount(0), "0")
        XCTAssertEqual(WatchKPIFormatter.leadCount(-3), "0")
    }

    /// Counts in [1, 99] render verbatim; 100+ caps out at "99+".
    func test_leadCount_capsAt99() {
        XCTAssertEqual(WatchKPIFormatter.leadCount(1), "1")
        XCTAssertEqual(WatchKPIFormatter.leadCount(42), "42")
        XCTAssertEqual(WatchKPIFormatter.leadCount(99), "99")
        XCTAssertEqual(WatchKPIFormatter.leadCount(100), "99+")
        XCTAssertEqual(WatchKPIFormatter.leadCount(9_999), "99+")
    }

    // MARK: - preview

    /// Empty / whitespace-only messages collapse to "" so the row
    /// never renders a one-character ghost.
    func test_preview_emptyAndWhitespaceCollapseToEmpty() {
        XCTAssertEqual(WatchKPIFormatter.preview(""), "")
        XCTAssertEqual(WatchKPIFormatter.preview("   "), "")
        XCTAssertEqual(WatchKPIFormatter.preview("\n\t\r"), "")
    }

    /// Short messages render verbatim with internal whitespace
    /// collapsed.
    func test_preview_shortMessage_rendersTrimmed() {
        XCTAssertEqual(
            WatchKPIFormatter.preview("Bonjour Mehdi"),
            "Bonjour Mehdi"
        )
        XCTAssertEqual(
            WatchKPIFormatter.preview("  Bonjour   Mehdi  "),
            "Bonjour Mehdi"
        )
    }

    /// Messages longer than `maxPreviewLength` get truncated with a
    /// trailing ellipsis (`…` = U+2026).
    func test_preview_longMessage_clipsWithEllipsis() {
        let long = String(repeating: "a", count: 100)
        let result = WatchKPIFormatter.preview(long)
        XCTAssertEqual(result.count, WatchKPIFormatter.maxPreviewLength + 1)
        XCTAssertTrue(result.hasSuffix("\u{2026}"))
    }

    // MARK: - elapsed

    /// Negative elapsed time clamps to "00:00" so the timer never
    /// renders "-0:01".
    func test_elapsed_negativeClampsToZero() {
        XCTAssertEqual(WatchKPIFormatter.elapsed(-1), "00:00")
        XCTAssertEqual(WatchKPIFormatter.elapsed(-1_000), "00:00")
    }

    /// Sub-hour durations render as "MM:SS".
    func test_elapsed_subHour_rendersMMSS() {
        XCTAssertEqual(WatchKPIFormatter.elapsed(0), "00:00")
        XCTAssertEqual(WatchKPIFormatter.elapsed(5), "00:05")
        XCTAssertEqual(WatchKPIFormatter.elapsed(65), "01:05")
        XCTAssertEqual(WatchKPIFormatter.elapsed(1_500), "25:00")     // 25min pomodoro
    }

    /// Hour+ durations render as "H:MM:SS".
    func test_elapsed_hourPlus_rendersHMMSS() {
        XCTAssertEqual(WatchKPIFormatter.elapsed(3_600), "1:00:00")
        XCTAssertEqual(WatchKPIFormatter.elapsed(3_725), "1:02:05")
        XCTAssertEqual(WatchKPIFormatter.elapsed(7_200), "2:00:00")
    }

    // MARK: - errorCount

    /// errorCount mirrors leadCount's clamp + cap contract.
    func test_errorCount_clampsAndCaps() {
        XCTAssertEqual(WatchKPIFormatter.errorCount(0), "0")
        XCTAssertEqual(WatchKPIFormatter.errorCount(-2), "0")
        XCTAssertEqual(WatchKPIFormatter.errorCount(7), "7")
        XCTAssertEqual(WatchKPIFormatter.errorCount(99), "99")
        XCTAssertEqual(WatchKPIFormatter.errorCount(150), "99+")
    }
}
