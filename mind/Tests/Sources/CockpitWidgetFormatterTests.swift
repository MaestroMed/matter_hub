import XCTest
@testable import GraphCore

/// v1.0-alpha.16 — Locks every formatter the Cockpit Lock Screen widget
/// renders on the two accessory families it supports. The widget
/// extension itself can't be imported here (separate appExtension
/// target sandboxed away from the host's unit-test bundle); putting
/// the formatters + the value type behind them in GraphCore is what
/// makes this surface testable.
final class CockpitWidgetFormatterTests: XCTestCase {

    // MARK: - formatLeadCount

    /// Single-digit lead counts pass through unchanged.
    func test_formatLeadCount_zero_isZero() {
        XCTAssertEqual(CockpitWidgetFormatter.formatLeadCount(0), "0")
    }

    func test_formatLeadCount_singleDigit_passThrough() {
        XCTAssertEqual(CockpitWidgetFormatter.formatLeadCount(5), "5")
    }

    func test_formatLeadCount_twoDigits_passThrough() {
        XCTAssertEqual(CockpitWidgetFormatter.formatLeadCount(42), "42")
    }

    /// Lead counts above 99 collapse to "99+" so the accessory inline
    /// family never blows its single-line budget on the Lock Screen.
    func test_formatLeadCount_overflow_collapsesToPlus() {
        XCTAssertEqual(CockpitWidgetFormatter.formatLeadCount(100), "99+")
        XCTAssertEqual(CockpitWidgetFormatter.formatLeadCount(1_234), "99+")
    }

    /// Defensive — a stray negative count (impossible via the provider
    /// but cheap to guard) collapses to "0" rather than rendering a
    /// minus sign on the widget.
    func test_formatLeadCount_negative_collapsesToZero() {
        XCTAssertEqual(CockpitWidgetFormatter.formatLeadCount(-1), "0")
        XCTAssertEqual(CockpitWidgetFormatter.formatLeadCount(-42), "0")
    }

    // MARK: - formatMRR

    /// Zero MRR renders as "0 €" (with a non-breaking space).
    func test_formatMRR_zero_rendersZeroEuro() {
        XCTAssertEqual(CockpitWidgetFormatter.formatMRR(0), "0\u{00A0}€")
    }

    /// Negative MRR (impossible from a stored row, but cheap to
    /// guard against arithmetic drift) clamps to zero.
    func test_formatMRR_negative_clampsToZero() {
        XCTAssertEqual(CockpitWidgetFormatter.formatMRR(-500), "0\u{00A0}€")
    }

    /// Thousand-grouping uses a non-breaking space so the number
    /// never wraps inside the narrow widget. Matches the HomeView
    /// KPI bar typography.
    func test_formatMRR_thousands_useNonBreakingSpace() {
        let result = CockpitWidgetFormatter.formatMRR(3_200)
        XCTAssertEqual(result, "3\u{00A0}200\u{00A0}€")
        // Locks the non-breaking-space convention explicitly.
        XCTAssertTrue(result.contains("\u{00A0}"))
        XCTAssertFalse(result.contains(" 200")) // no regular space
    }

    /// Large MRR amounts still group correctly with multiple separators.
    func test_formatMRR_largeAmount_groupsEveryThousand() {
        XCTAssertEqual(
            CockpitWidgetFormatter.formatMRR(1_234_567),
            "1\u{00A0}234\u{00A0}567\u{00A0}€"
        )
    }

    // MARK: - rectangularHeader

    /// Empty inbox surfaces the FR "Aucun nouveau lead" idle copy
    /// (cockpit is FR-first per Mehdi convention).
    func test_rectangularHeader_zeroLeads_isEmptyState() {
        let snapshot = CockpitWidgetSnapshot(
            date: .now,
            newLeadCount: 0,
            activeProjectsCount: 6,
            totalMRR_EUR: 3_200,
            lastLeadContactName: nil,
            lastLeadProjectName: nil
        )
        XCTAssertEqual(
            CockpitWidgetFormatter.rectangularHeader(for: snapshot),
            "Aucun nouveau lead"
        )
    }

    /// Singular noun on the 1-lead edge case (iOS HIG pluralisation).
    func test_rectangularHeader_oneLead_isSingular() {
        let snapshot = CockpitWidgetSnapshot(
            date: .now,
            newLeadCount: 1,
            activeProjectsCount: 6,
            totalMRR_EUR: 3_200,
            lastLeadContactName: "Sara",
            lastLeadProjectName: "IEF & Co"
        )
        XCTAssertEqual(
            CockpitWidgetFormatter.rectangularHeader(for: snapshot),
            "1 nouveau lead"
        )
    }

    /// Plural noun for any count >= 2. Locks the boundary the widget
    /// renders most often.
    func test_rectangularHeader_pluralLeads_isPlural() {
        let snapshot = CockpitWidgetSnapshot(
            date: .now,
            newLeadCount: 7,
            activeProjectsCount: 6,
            totalMRR_EUR: 3_200,
            lastLeadContactName: "Sara",
            lastLeadProjectName: "IEF & Co"
        )
        XCTAssertEqual(
            CockpitWidgetFormatter.rectangularHeader(for: snapshot),
            "7 nouveaux leads"
        )
    }

    /// Overflowing lead counts route the rectangular header through
    /// the same `formatLeadCount` clamp the inline family uses.
    func test_rectangularHeader_overflow_clamped() {
        let snapshot = CockpitWidgetSnapshot(
            date: .now,
            newLeadCount: 250,
            activeProjectsCount: 6,
            totalMRR_EUR: 3_200,
            lastLeadContactName: "Sara",
            lastLeadProjectName: "IEF & Co"
        )
        XCTAssertEqual(
            CockpitWidgetFormatter.rectangularHeader(for: snapshot),
            "99+ nouveaux leads"
        )
    }

    // MARK: - rectangularBody

    /// Both contact + project known → "Name · Project" body line.
    func test_rectangularBody_contactAndProject_joined() {
        let snapshot = CockpitWidgetSnapshot(
            date: .now,
            newLeadCount: 3,
            activeProjectsCount: 6,
            totalMRR_EUR: 3_200,
            lastLeadContactName: "Sara",
            lastLeadProjectName: "IEF & Co"
        )
        XCTAssertEqual(
            CockpitWidgetFormatter.rectangularBody(for: snapshot),
            "Sara · IEF & Co"
        )
    }

    /// Contact known, project unresolved → contact-only body line.
    func test_rectangularBody_contactOnly_carriesName() {
        let snapshot = CockpitWidgetSnapshot(
            date: .now,
            newLeadCount: 1,
            activeProjectsCount: 6,
            totalMRR_EUR: 3_200,
            lastLeadContactName: "Anonymous Visitor",
            lastLeadProjectName: nil
        )
        XCTAssertEqual(
            CockpitWidgetFormatter.rectangularBody(for: snapshot),
            "Anonymous Visitor"
        )
    }

    /// Empty contact (both nil) → MRR fallback body line so the widget
    /// stays useful on the idle day.
    func test_rectangularBody_emptyInbox_fallsBackToMRR() {
        let snapshot = CockpitWidgetSnapshot(
            date: .now,
            newLeadCount: 0,
            activeProjectsCount: 6,
            totalMRR_EUR: 3_200,
            lastLeadContactName: nil,
            lastLeadProjectName: nil
        )
        XCTAssertEqual(
            CockpitWidgetFormatter.rectangularBody(for: snapshot),
            "3\u{00A0}200\u{00A0}€ MRR"
        )
    }

    /// Empty-string contact (defensive guard against a Lead with an
    /// empty `contactName` field — happens on legal-page forms) folds
    /// to the MRR fallback rather than rendering a stray dash.
    func test_rectangularBody_emptyStringContact_fallsBackToMRR() {
        let snapshot = CockpitWidgetSnapshot(
            date: .now,
            newLeadCount: 1,
            activeProjectsCount: 6,
            totalMRR_EUR: 1_500,
            lastLeadContactName: "",
            lastLeadProjectName: nil
        )
        XCTAssertEqual(
            CockpitWidgetFormatter.rectangularBody(for: snapshot),
            "1\u{00A0}500\u{00A0}€ MRR"
        )
    }

    // MARK: - inlineBody

    /// The inline family always carries the brand prefix so a reader
    /// scanning the Lock Screen knows the row belongs to MIND.
    func test_inlineBody_alwaysCarriesBrandPrefix() {
        let snapshot = CockpitWidgetSnapshot(
            date: .now,
            newLeadCount: 3,
            activeProjectsCount: 6,
            totalMRR_EUR: 3_200,
            lastLeadContactName: "Sara",
            lastLeadProjectName: "IEF & Co"
        )
        XCTAssertTrue(
            CockpitWidgetFormatter.inlineBody(for: snapshot).hasPrefix("MIND ·")
        )
    }

    /// Singular noun on the 1-lead edge case, same as the rectangular
    /// header.
    func test_inlineBody_oneLead_isSingular() {
        let snapshot = CockpitWidgetSnapshot(
            date: .now,
            newLeadCount: 1,
            activeProjectsCount: 6,
            totalMRR_EUR: 3_200,
            lastLeadContactName: "Sara",
            lastLeadProjectName: "IEF & Co"
        )
        XCTAssertEqual(
            CockpitWidgetFormatter.inlineBody(for: snapshot),
            "MIND · 1 lead"
        )
    }

    /// Plural form + count formatted through `formatLeadCount` so the
    /// inline branch stays consistent with the rectangular header.
    func test_inlineBody_pluralLeads_carriesFormattedCount() {
        let snapshot = CockpitWidgetSnapshot(
            date: .now,
            newLeadCount: 12,
            activeProjectsCount: 6,
            totalMRR_EUR: 3_200,
            lastLeadContactName: nil,
            lastLeadProjectName: nil
        )
        XCTAssertEqual(
            CockpitWidgetFormatter.inlineBody(for: snapshot),
            "MIND · 12 leads"
        )
    }

    /// Zero-count inline body uses the plural form ("0 leads") to
    /// keep the row legible — the rectangular family owns the empty-
    /// state copy.
    func test_inlineBody_zeroLeads_pluralForm() {
        let snapshot = CockpitWidgetSnapshot(
            date: .now,
            newLeadCount: 0,
            activeProjectsCount: 0,
            totalMRR_EUR: 0,
            lastLeadContactName: nil,
            lastLeadProjectName: nil
        )
        XCTAssertEqual(
            CockpitWidgetFormatter.inlineBody(for: snapshot),
            "MIND · 0 leads"
        )
    }

    /// Overflowing inline counts route through `formatLeadCount`.
    func test_inlineBody_overflow_clamped() {
        let snapshot = CockpitWidgetSnapshot(
            date: .now,
            newLeadCount: 500,
            activeProjectsCount: 6,
            totalMRR_EUR: 3_200,
            lastLeadContactName: nil,
            lastLeadProjectName: nil
        )
        XCTAssertEqual(
            CockpitWidgetFormatter.inlineBody(for: snapshot),
            "MIND · 99+ leads"
        )
    }

    // MARK: - deepLinkURL

    /// The widget's `widgetURL(...)` reads this exact URL — any drift
    /// would silently break Lock Screen taps. `RootView.onOpenURL`
    /// routes the `leads` host to the Home tab.
    func test_deepLinkURL_shape() {
        XCTAssertEqual(
            CockpitWidgetFormatter.deepLinkURL.absoluteString,
            "mind://leads"
        )
        XCTAssertEqual(CockpitWidgetFormatter.deepLinkURL.scheme, "mind")
        XCTAssertEqual(CockpitWidgetFormatter.deepLinkURL.host, "leads")
    }

    // MARK: - CockpitWidgetSnapshot

    /// Placeholder constant stays alive across both consumers (widget
    /// + tests). Locked here so a drift in the canonical sample
    /// becomes a test failure rather than a silent preview regression.
    func test_snapshot_placeholder_preserved() {
        XCTAssertEqual(CockpitWidgetSnapshot.placeholder.newLeadCount, 3)
        XCTAssertEqual(CockpitWidgetSnapshot.placeholder.activeProjectsCount, 6)
        XCTAssertEqual(CockpitWidgetSnapshot.placeholder.totalMRR_EUR, 3_200)
        XCTAssertEqual(
            CockpitWidgetSnapshot.placeholder.lastLeadContactName,
            "Sara"
        )
        XCTAssertEqual(
            CockpitWidgetSnapshot.placeholder.lastLeadProjectName,
            "IEF & Co"
        )
    }

    /// Empty preset carries zeros + nils so the provider's empty-inbox
    /// branch surfaces the MRR fallback rectangular body without re-
    /// rolling the value type at the call site.
    func test_snapshot_empty_carriesZerosAndNils() {
        XCTAssertEqual(CockpitWidgetSnapshot.empty.newLeadCount, 0)
        XCTAssertEqual(CockpitWidgetSnapshot.empty.activeProjectsCount, 0)
        XCTAssertEqual(CockpitWidgetSnapshot.empty.totalMRR_EUR, 0)
        XCTAssertNil(CockpitWidgetSnapshot.empty.lastLeadContactName)
        XCTAssertNil(CockpitWidgetSnapshot.empty.lastLeadProjectName)
    }

    /// Equatable conformance round-trips through identical fields —
    /// used by future SwiftUI animations + by any planned widget
    /// regression test that needs to assert "the snapshot didn't move
    /// between two timeline reloads".
    func test_snapshot_equatable_identicalFields_compareEqual() {
        let pinnedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let a = CockpitWidgetSnapshot(
            date: pinnedDate,
            newLeadCount: 3,
            activeProjectsCount: 6,
            totalMRR_EUR: 3_200,
            lastLeadContactName: "Sara",
            lastLeadProjectName: "IEF & Co"
        )
        let b = CockpitWidgetSnapshot(
            date: pinnedDate,
            newLeadCount: 3,
            activeProjectsCount: 6,
            totalMRR_EUR: 3_200,
            lastLeadContactName: "Sara",
            lastLeadProjectName: "IEF & Co"
        )
        XCTAssertEqual(a, b)
    }

    /// Equatable conformance separates different lead counts even when
    /// every other field is shared. Defends against accidental short-
    /// circuit comparisons.
    func test_snapshot_equatable_differingLeadCount_compareUnequal() {
        let pinnedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let a = CockpitWidgetSnapshot(
            date: pinnedDate,
            newLeadCount: 3,
            activeProjectsCount: 6,
            totalMRR_EUR: 3_200,
            lastLeadContactName: "Sara",
            lastLeadProjectName: "IEF & Co"
        )
        let b = CockpitWidgetSnapshot(
            date: pinnedDate,
            newLeadCount: 4,
            activeProjectsCount: 6,
            totalMRR_EUR: 3_200,
            lastLeadContactName: "Sara",
            lastLeadProjectName: "IEF & Co"
        )
        XCTAssertNotEqual(a, b)
    }

    /// Equatable conformance separates different MRR amounts.
    func test_snapshot_equatable_differingMRR_compareUnequal() {
        let pinnedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let a = CockpitWidgetSnapshot(
            date: pinnedDate,
            newLeadCount: 3,
            activeProjectsCount: 6,
            totalMRR_EUR: 3_200,
            lastLeadContactName: nil,
            lastLeadProjectName: nil
        )
        let b = CockpitWidgetSnapshot(
            date: pinnedDate,
            newLeadCount: 3,
            activeProjectsCount: 6,
            totalMRR_EUR: 4_500,
            lastLeadContactName: nil,
            lastLeadProjectName: nil
        )
        XCTAssertNotEqual(a, b)
    }
}
