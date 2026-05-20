import Foundation

/// v0.31 — Convenience factory bundling the steps the InvoiceSheet
/// runs every time the user taps "Générer la facture":
///
///   1. Ask `InvoiceStore.shared.nextNumber()` for the next sequential
///      MIND number.
///   2. Build the `Invoice` value type with the user's amount / VAT /
///      description.
///   3. If a Stripe Payment Link prefix exists, compute the per-
///      invoice URL via `InvoiceStripeLinkBuilder`.
///   4. Persist via `InvoiceStore.shared.save(_:)`.
///
/// Pure function on the input parameters — no UIKit, no MINDPreferences
/// dep. The caller in the app layer reads MINDPreferences and feeds
/// the values in, which keeps InvoiceKit usable from a unit test
/// without bringing the Settings module into the test bundle's link
/// graph.
public enum InvoiceFactory {

    /// Builds a fresh draft invoice + the Stripe Payment Link (when a
    /// base is provided), and persists it via the supplied store.
    /// Returns the freshly-minted invoice so the caller can hand it
    /// straight to `InvoicePDFRenderer.render(_:)` for sharing.
    public static func mintDraft(
        clientNodeID: UUID,
        clientName: String,
        clientEmail: String?,
        amountEUR: Double,
        vatPercent: Double,
        description: String,
        stripePaymentLinkBase: String?,
        branding: ConsultantBranding,
        store: InvoiceStore = .shared,
        now: Date = .now
    ) async -> Invoice {
        let number = await store.nextNumber(now: now)
        let issueDate = now
        let dueDate = Invoice.defaultDueDate(from: issueDate)
        let stripeURL: String? = {
            guard let base = stripePaymentLinkBase, !base.isEmpty else { return nil }
            return InvoiceStripeLinkBuilder.appendAmount(
                base: base,
                amountEUR: Self.applyVAT(amountEUR: amountEUR, vatPercent: vatPercent)
            )
        }()
        let invoice = Invoice(
            number: number,
            issueDate: issueDate,
            dueDate: dueDate,
            clientNodeID: clientNodeID,
            clientName: clientName,
            clientEmail: clientEmail,
            amountEUR: amountEUR,
            vatPercent: vatPercent,
            description: description,
            status: .draft,
            stripePaymentLinkURL: stripeURL,
            consultantBranding: branding
        )
        await store.save(invoice)
        return invoice
    }

    /// Default suggested description used by the InvoiceSheet form.
    /// FR copy, client-name interpolated. Exposed publicly so the
    /// LocalizationTests pin the template format and a future
    /// re-rebrand (`Audit MIND` → something else) trips a test.
    public static func defaultDescription(for clientName: String) -> String {
        "Mission audit + recommandations pour \(clientName)"
    }

    /// Same VAT math `Invoice` does internally — duplicated here so
    /// the factory can hand the Stripe builder the TTC total without
    /// instantiating the `Invoice` first (we need the URL *before*
    /// the `Invoice` init so it can be stored on the struct).
    private static func applyVAT(amountEUR: Double, vatPercent: Double) -> Double {
        let clamped = max(0, amountEUR)
        let pct = max(0, min(100, vatPercent))
        let ttc = clamped + clamped * pct / 100.0
        return Invoice.roundedAmount(ttc)
    }
}
