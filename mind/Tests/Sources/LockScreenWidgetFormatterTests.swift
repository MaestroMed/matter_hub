import XCTest
@testable import GraphCore

/// v0.27.1 — Locks every formatter the Lock Screen widget renders on
/// the three accessory families. The widget extension itself can't be
/// imported here (separate appExtension target sandboxed away from
/// the host's unit-test bundle); putting the formatters + the value
/// type behind them in GraphCore is what makes this surface testable.
final class LockScreenWidgetFormatterTests: XCTestCase {

    // MARK: - formatCount

    /// Single-digit counts pass through unchanged.
    func test_formatCount_zero_isZero() {
        XCTAssertEqual(LockScreenWidgetFormatter.formatCount(0), "0")
    }

    func test_formatCount_singleDigit_passThrough() {
        XCTAssertEqual(LockScreenWidgetFormatter.formatCount(7), "7")
    }

    /// Two-digit counts pass through. The widget's circular family
    /// keeps its 18pt glyph at this boundary.
    func test_formatCount_twoDigits_passThrough() {
        XCTAssertEqual(LockScreenWidgetFormatter.formatCount(42), "42")
    }

    /// Three-digit counts pass through. The widget's circular family
    /// auto-drops the glyph to 14pt at >= 100.
    func test_formatCount_threeDigits_passThrough() {
        XCTAssertEqual(LockScreenWidgetFormatter.formatCount(999), "999")
    }

    /// Counts above 999 collapse to "999+" so the circular dial's
    /// 3-glyph budget never overflows.
    func test_formatCount_overflow_collapsesToPlus() {
        XCTAssertEqual(LockScreenWidgetFormatter.formatCount(1_000), "999+")
        XCTAssertEqual(LockScreenWidgetFormatter.formatCount(12_345), "999+")
    }

    /// Defensive — a stray negative count (impossible via the
    /// provider, but cheap to guard) collapses to "0" rather than
    /// rendering a minus sign on the dial.
    func test_formatCount_negative_collapsesToZero() {
        XCTAssertEqual(LockScreenWidgetFormatter.formatCount(-1), "0")
        XCTAssertEqual(LockScreenWidgetFormatter.formatCount(-42), "0")
    }

    // MARK: - rectangularHeader

    /// Empty graph surfaces a CTA-aware header line. The widget's
    /// rectangular body pairs this with the "Tap to capture" copy.
    func test_rectangularHeader_zeroCount_isEmptyGraph() {
        let snapshot = LockScreenEntrySnapshot(
            date: .now,
            totalCount: 0,
            lastTitle: nil
        )
        XCTAssertEqual(
            LockScreenWidgetFormatter.rectangularHeader(for: snapshot),
            "Empty graph"
        )
    }

    /// Singular noun on the 1-thought edge case — the iOS HIG
    /// pluralisation pattern. No translation work yet (FR localisation
    /// of the rectangular header is a future iteration).
    func test_rectangularHeader_oneCount_isSingular() {
        let snapshot = LockScreenEntrySnapshot(
            date: .now,
            totalCount: 1,
            lastTitle: "Sole thought"
        )
        XCTAssertEqual(
            LockScreenWidgetFormatter.rectangularHeader(for: snapshot),
            "1 thought"
        )
    }

    /// Plural noun for any non-1 count >= 2. Locks the boundary the
    /// widget renders most often.
    func test_rectangularHeader_pluralCount_isPlural() {
        let snapshot = LockScreenEntrySnapshot(
            date: .now,
            totalCount: 17,
            lastTitle: nil
        )
        XCTAssertEqual(
            LockScreenWidgetFormatter.rectangularHeader(for: snapshot),
            "17 thoughts"
        )
    }

    /// Overflowing counts route the rectangular header through the
    /// same `formatCount` clamp the circular family uses.
    func test_rectangularHeader_overflow_clamped() {
        let snapshot = LockScreenEntrySnapshot(
            date: .now,
            totalCount: 5_000,
            lastTitle: nil
        )
        XCTAssertEqual(
            LockScreenWidgetFormatter.rectangularHeader(for: snapshot),
            "999+ thoughts"
        )
    }

    // MARK: - inlineBody

    /// The inline family always carries the brand prefix so a reader
    /// scanning the Lock Screen knows the row belongs to MIND.
    func test_inlineBody_alwaysCarriesBrandPrefix() {
        let snapshot = LockScreenEntrySnapshot(
            date: .now,
            totalCount: 42,
            lastTitle: nil
        )
        XCTAssertTrue(
            LockScreenWidgetFormatter.inlineBody(for: snapshot).hasPrefix("MIND ·")
        )
    }

    /// Singular noun on the 1-thought edge case, same as the
    /// rectangular family.
    func test_inlineBody_oneCount_isSingular() {
        let snapshot = LockScreenEntrySnapshot(
            date: .now,
            totalCount: 1,
            lastTitle: nil
        )
        XCTAssertEqual(
            LockScreenWidgetFormatter.inlineBody(for: snapshot),
            "MIND · 1 thought"
        )
    }

    /// Plural + count formatted through `formatCount` so the inline
    /// branch stays consistent with the circular and rectangular ones.
    func test_inlineBody_pluralCount_carriesFormattedCount() {
        let snapshot = LockScreenEntrySnapshot(
            date: .now,
            totalCount: 250,
            lastTitle: nil
        )
        XCTAssertEqual(
            LockScreenWidgetFormatter.inlineBody(for: snapshot),
            "MIND · 250 thoughts"
        )
    }

    /// Zero-count inline body uses the plural form ("0 thoughts") to
    /// keep the row legible — empty state copy is owned by the
    /// rectangular family alone.
    func test_inlineBody_zeroCount_pluralForm() {
        let snapshot = LockScreenEntrySnapshot(
            date: .now,
            totalCount: 0,
            lastTitle: nil
        )
        XCTAssertEqual(
            LockScreenWidgetFormatter.inlineBody(for: snapshot),
            "MIND · 0 thoughts"
        )
    }

    // MARK: - deepLinkURL

    /// The widget's `widgetURL(...)` reads this exact URL — any
    /// drift would silently break Lock Screen taps. The host App's
    /// `mind://` scheme parser routes the `lock` host to a fresh
    /// capture CTA on the Home tab.
    func test_deepLinkURL_shape() {
        XCTAssertEqual(
            LockScreenWidgetFormatter.deepLinkURL.absoluteString,
            "mind://lock"
        )
        XCTAssertEqual(LockScreenWidgetFormatter.deepLinkURL.scheme, "mind")
        XCTAssertEqual(LockScreenWidgetFormatter.deepLinkURL.host, "lock")
    }

    // MARK: - LockScreenEntrySnapshot

    /// Placeholder constant stays alive across both consumers (widget
    /// + tests). Locked here so a drift in the canonical sample
    /// (count or title) becomes a test failure rather than a silent
    /// preview regression.
    func test_snapshot_placeholder_preserved() {
        XCTAssertEqual(LockScreenEntrySnapshot.placeholder.totalCount, 42)
        XCTAssertEqual(
            LockScreenEntrySnapshot.placeholder.lastTitle,
            "Spark from this morning"
        )
    }

    /// Empty preset carries 0 + nil so the provider's empty-graph
    /// branch surfaces the "Tap to capture" rectangular CTA without
    /// re-rolling the value type at the call site.
    func test_snapshot_empty_carriesZeroAndNil() {
        XCTAssertEqual(LockScreenEntrySnapshot.empty.totalCount, 0)
        XCTAssertNil(LockScreenEntrySnapshot.empty.lastTitle)
    }

    /// Equatable conformance round-trips through identical fields.
    /// Used by future SwiftUI animations + by any planned widget
    /// regression test that needs to assert "the snapshot didn't
    /// move between two timeline reloads".
    func test_snapshot_equatable_identicalFields_compareEqual() {
        let pinnedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let a = LockScreenEntrySnapshot(
            date: pinnedDate,
            totalCount: 7,
            lastTitle: "hello"
        )
        let b = LockScreenEntrySnapshot(
            date: pinnedDate,
            totalCount: 7,
            lastTitle: "hello"
        )
        XCTAssertEqual(a, b)
    }

    /// Equatable conformance separates different counts even when the
    /// title is shared. Defends against accidental short-circuit
    /// comparisons.
    func test_snapshot_equatable_differingCount_compareUnequal() {
        let pinnedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let a = LockScreenEntrySnapshot(
            date: pinnedDate,
            totalCount: 7,
            lastTitle: "hello"
        )
        let b = LockScreenEntrySnapshot(
            date: pinnedDate,
            totalCount: 8,
            lastTitle: "hello"
        )
        XCTAssertNotEqual(a, b)
    }
}
