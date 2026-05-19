import XCTest
@testable import InvoiceKit

/// v0.31 — InvoiceKit core type tests.
///
/// Locks the pure parts of the Stripe Invoice Generator feature:
///
/// 1. `Invoice` value type: amount math (HT / TTC / VAT 0 / VAT 20),
///    rounding edge cases, init defensiveness (negative clamp,
///    default due date), Codable round-trip.
/// 2. Number formatter: `MIND-YYYY-NNNN` shape.
/// 3. `InvoiceStripeLinkBuilder.appendAmount(...)`: cent rounding,
///    empty base nil, query parameter preservation, duplicate
///    avoidance.
/// 4. `InvoiceStore` actor: sequential numbering bumps + the
///    year-roll-over reset.
/// 5. `InvoicePDFRenderer.render(_:)`: non-empty Data, optional
///    SIRET / IBAN graceful skip.
/// 6. `InvoiceStatus` transitions via `markedSent` / `markedPaid`
///    / `isOverdue(now:)`.
final class InvoiceTests: XCTestCase {

    // MARK: - Number formatter

    func test_formatNumber_padsYearAndOrdinalTo4Digits() {
        XCTAssertEqual(
            Invoice.formatNumber(year: 2026, ordinal: 1),
            "MIND-2026-0001",
            "First invoice of 2026 should read MIND-2026-0001."
        )
        XCTAssertEqual(
            Invoice.formatNumber(year: 2026, ordinal: 42),
            "MIND-2026-0042"
        )
        XCTAssertEqual(
            Invoice.formatNumber(year: 2099, ordinal: 9999),
            "MIND-2099-9999"
        )
    }

    func test_formatNumber_clampsOrdinalToAtLeast1() {
        // Defensive: a zero / negative ordinal should still produce a
        // legal-looking number rather than "MIND-2026-0000".
        XCTAssertEqual(
            Invoice.formatNumber(year: 2026, ordinal: 0),
            "MIND-2026-0001"
        )
        XCTAssertEqual(
            Invoice.formatNumber(year: 2026, ordinal: -7),
            "MIND-2026-0001"
        )
    }

    // MARK: - VAT math

    func test_amountHT_withVAT20_keepsBaseUntouched() {
        let invoice = makeInvoice(amountEUR: 1_000, vatPercent: 20)
        XCTAssertEqual(invoice.amountHT, 1_000.00, accuracy: 0.001)
    }

    func test_amountTTC_withVAT20_multipliesBy1_20() {
        let invoice = makeInvoice(amountEUR: 1_000, vatPercent: 20)
        XCTAssertEqual(invoice.amountTTC, 1_200.00, accuracy: 0.001,
                       "HT × 1.20 should yield TTC for 20% VAT.")
        XCTAssertEqual(invoice.amountVAT, 200.00, accuracy: 0.001)
    }

    func test_amountTTC_withVAT0_equalsHT() {
        let invoice = makeInvoice(amountEUR: 750, vatPercent: 0)
        XCTAssertEqual(invoice.amountHT, 750.00, accuracy: 0.001)
        XCTAssertEqual(invoice.amountTTC, 750.00, accuracy: 0.001,
                       "VAT 0% should leave the total equal to HT.")
        XCTAssertEqual(invoice.amountVAT, 0.00, accuracy: 0.001)
    }

    func test_amountRounding_centsRoundedTo2Decimals() {
        // 12.345 should round to 12.35 (banker's rounding to even
        // would round to 12.34 — but Swift's `rounded()` defaults to
        // schoolbook half-away-from-zero, which produces 12.35).
        let invoice = makeInvoice(amountEUR: 12.345, vatPercent: 0)
        XCTAssertEqual(invoice.amountHT, 12.35, accuracy: 0.001,
                       "12.345 should round to 12.35 at the 2nd decimal.")
    }

    // MARK: - Init defensiveness

    func test_init_negativeAmount_clampsToZero() {
        let invoice = makeInvoice(amountEUR: -100, vatPercent: 20)
        XCTAssertEqual(invoice.amountHT, 0.00, accuracy: 0.001)
        XCTAssertEqual(invoice.amountTTC, 0.00, accuracy: 0.001)
    }

    func test_init_defaultDueDate_isIssueDatePlus30Days() {
        let issueDate = Date(timeIntervalSince1970: 1_700_000_000)
        let invoice = Invoice(
            number: "MIND-2024-0001",
            issueDate: issueDate,
            clientNodeID: UUID(),
            clientName: "Acme",
            amountEUR: 100,
            description: "Test"
        )
        let calendar = Calendar(identifier: .gregorian)
        let expected = calendar.date(byAdding: .day, value: 30, to: issueDate)!
        XCTAssertEqual(
            invoice.dueDate.timeIntervalSinceReferenceDate,
            expected.timeIntervalSinceReferenceDate,
            accuracy: 1,
            "Default due date should be issueDate + 30 days."
        )
    }

    // MARK: - Codable round-trip

    func test_codable_roundTrip_preservesEveryField() throws {
        let branding = ConsultantBranding(
            name: "Mehdi Nafaa",
            address: "12 rue du Code\n75011 Paris",
            siret: "12345678901234",
            vatNumber: "FR12345678901",
            iban: "FR7630006000011234567890189",
            email: "meehdi.n@gmail.com",
            phone: "+33 6 12 34 56 78"
        )
        let original = Invoice(
            id: UUID(),
            number: "MIND-2026-0001",
            issueDate: Date(timeIntervalSince1970: 1_700_000_000),
            dueDate: Date(timeIntervalSince1970: 1_702_592_000),
            clientNodeID: UUID(),
            clientName: "Acme SAS",
            clientEmail: "ops@acme.com",
            amountEUR: 4_500,
            vatPercent: 20,
            description: "Mission audit + recommandations pour Acme SAS",
            status: .sent,
            paidAt: nil,
            stripePaymentLinkURL: "https://buy.stripe.com/test?prefilled_amount=540000",
            consultantBranding: branding
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Invoice.self, from: data)

        XCTAssertEqual(decoded, original,
                       "Codable round-trip must preserve every field, " +
                       "including the full ConsultantBranding nesting.")
    }

    // MARK: - Status transitions

    func test_markedSent_flipsStatusAndPreservesIDs() {
        let initial = makeInvoice(amountEUR: 100, vatPercent: 20)
        XCTAssertEqual(initial.status, .draft)
        let sent = initial.markedSent(stripePaymentLinkURL: "https://buy.stripe.com/x")
        XCTAssertEqual(sent.status, .sent)
        XCTAssertEqual(sent.id, initial.id, "id must not change across status flip.")
        XCTAssertEqual(sent.number, initial.number, "number must not change across status flip.")
        XCTAssertEqual(sent.stripePaymentLinkURL, "https://buy.stripe.com/x")
    }

    func test_markedPaid_flipsStatusAndStampsPaidAt() {
        let sent = makeInvoice(amountEUR: 100, vatPercent: 20).markedSent()
        let stamp = Date(timeIntervalSince1970: 1_700_500_000)
        let paid = sent.markedPaid(at: stamp)
        XCTAssertEqual(paid.status, .paid)
        XCTAssertEqual(paid.paidAt, stamp)
    }

    func test_isOverdue_trueWhenSentAndPastDue() {
        let issueDate = Date(timeIntervalSince1970: 1_700_000_000)
        let dueDate   = Date(timeIntervalSince1970: 1_702_592_000)
        let now       = Date(timeIntervalSince1970: 1_705_000_000)
        let invoice = Invoice(
            number: "MIND-2024-0001",
            issueDate: issueDate,
            dueDate: dueDate,
            clientNodeID: UUID(),
            clientName: "Late",
            amountEUR: 100,
            description: "x",
            status: .sent
        )
        XCTAssertTrue(invoice.isOverdue(now: now),
                      "An invoice with status .sent past its dueDate must be overdue.")
    }

    func test_isOverdue_falseWhenStillDraft() {
        let issueDate = Date(timeIntervalSince1970: 1_700_000_000)
        let dueDate   = Date(timeIntervalSince1970: 1_702_592_000)
        let now       = Date(timeIntervalSince1970: 1_705_000_000)
        let invoice = Invoice(
            number: "MIND-2024-0001",
            issueDate: issueDate,
            dueDate: dueDate,
            clientNodeID: UUID(),
            clientName: "Still draft",
            amountEUR: 100,
            description: "x",
            status: .draft
        )
        XCTAssertFalse(invoice.isOverdue(now: now),
                       "A draft invoice can't be overdue even past its dueDate.")
    }

    // MARK: - Stripe Payment Link builder

    func test_stripeLinkBuilder_appendsPrefilledAmountAsCents() {
        let base = "https://buy.stripe.com/3cs5ll"
        let url = InvoiceStripeLinkBuilder.appendAmount(base: base, amountEUR: 1_200.00)
        XCTAssertNotNil(url)
        XCTAssertTrue(url!.contains("prefilled_amount=120000"),
                      "1200 EUR should append `prefilled_amount=120000` (cents).")
    }

    func test_stripeLinkBuilder_emptyBase_returnsNil() {
        XCTAssertNil(InvoiceStripeLinkBuilder.appendAmount(base: "", amountEUR: 100))
        XCTAssertNil(InvoiceStripeLinkBuilder.appendAmount(base: "   ", amountEUR: 100))
    }

    func test_stripeLinkBuilder_replacesExistingPrefilledAmount_avoidsDuplicate() {
        let base = "https://buy.stripe.com/x?prefilled_amount=999&foo=bar"
        let url = InvoiceStripeLinkBuilder.appendAmount(base: base, amountEUR: 50)
        XCTAssertNotNil(url)
        // Only one prefilled_amount should appear in the final URL.
        let count = url!.components(separatedBy: "prefilled_amount=").count - 1
        XCTAssertEqual(count, 1, "Existing prefilled_amount should be replaced, not duplicated.")
        XCTAssertTrue(url!.contains("prefilled_amount=5000"))
        XCTAssertTrue(url!.contains("foo=bar"),
                      "Unrelated query parameters must be preserved.")
    }

    // MARK: - PDF renderer

    func test_pdfRenderer_producesNonEmptyData() {
        let invoice = makeInvoice(amountEUR: 1_500, vatPercent: 20)
        let pdf = InvoicePDFRenderer.render(invoice)
        XCTAssertFalse(pdf.isEmpty,
                       "PDF renderer must produce non-empty bytes on iOS.")
        XCTAssertTrue(pdf.starts(with: Data("%PDF".utf8)),
                      "Output should be a valid PDF (begin with `%PDF` magic).")
    }

    func test_pdfRenderer_invoiceWithoutSIRET_stillRenders() {
        let bare = ConsultantBranding(name: "Solo", siret: nil, iban: nil)
        let invoice = Invoice(
            number: "MIND-2026-0007",
            clientNodeID: UUID(),
            clientName: "Test",
            amountEUR: 800,
            vatPercent: 0,
            description: "Audit",
            consultantBranding: bare
        )
        let pdf = InvoicePDFRenderer.render(invoice)
        XCTAssertFalse(pdf.isEmpty,
                       "A consultant without SIRET / IBAN must still ship a valid PDF.")
    }

    // MARK: - InvoiceStore actor

    func test_invoiceStore_nextNumber_incrementsSequentially() async throws {
        let store = makeStore()
        let now = Self.fixedDate(year: 2026, month: 5, day: 19)
        let first  = await store.nextNumber(now: now)
        let second = await store.nextNumber(now: now)
        let third  = await store.nextNumber(now: now)
        XCTAssertEqual(first,  "MIND-2026-0001")
        XCTAssertEqual(second, "MIND-2026-0002")
        XCTAssertEqual(third,  "MIND-2026-0003")
    }

    func test_invoiceStore_yearRollover_resetsOrdinal() async throws {
        let store = makeStore()
        let dec = Self.fixedDate(year: 2026, month: 12, day: 31)
        _ = await store.nextNumber(now: dec)
        _ = await store.nextNumber(now: dec)
        let firstOf2027 = await store.nextNumber(
            now: Self.fixedDate(year: 2027, month: 1, day: 1)
        )
        XCTAssertEqual(firstOf2027, "MIND-2027-0001",
                       "Crossing into a new year should reset the ordinal back to 0001.")
    }

    func test_invoiceStore_saveAndLoad_roundTripsInvoice() async throws {
        let store = makeStore()
        let invoice = makeInvoice(amountEUR: 500, vatPercent: 20)
        await store.save(invoice)
        let loaded = await store.load(invoice.id)
        XCTAssertEqual(loaded, invoice)
    }

    // MARK: - InvoiceFactory

    func test_factory_defaultDescription_includesClientName() {
        let copy = InvoiceFactory.defaultDescription(for: "Acme")
        XCTAssertTrue(copy.contains("Acme"),
                      "Default description must interpolate the client name.")
        XCTAssertTrue(copy.localizedCaseInsensitiveContains("audit"),
                      "Default description must mention an audit.")
    }

    // MARK: - Helpers

    private func makeInvoice(
        amountEUR: Double,
        vatPercent: Double
    ) -> Invoice {
        Invoice(
            number: "MIND-2026-0001",
            clientNodeID: UUID(),
            clientName: "Acme",
            clientEmail: "ops@acme.com",
            amountEUR: amountEUR,
            vatPercent: vatPercent,
            description: "Test mission"
        )
    }

    private func makeStore() -> InvoiceStore {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("InvoiceStoreTests-\(UUID().uuidString)", isDirectory: true)
        return InvoiceStore(rootURL: temp)
    }

    private static func fixedDate(year: Int, month: Int, day: Int) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.calendar = Calendar(identifier: .gregorian)
        return comps.date ?? Date()
    }
}
