import Foundation

/// v0.31 — Pure helper that appends a `prefilled_amount` query
/// parameter to a Stripe Payment Link the user pasted into Settings
/// once. Stripe Payment Links accept an `prefilled_amount` integer
/// in the smallest currency unit (cents for EUR), which the checkout
/// page pre-fills as the suggested amount. The customer can still
/// adjust it, but the default lands right on the invoice total so
/// the friction stays minimal.
///
/// Lives outside `Invoice` because the URL math has nothing to do
/// with the invoice value type — it's a pure string transformation
/// that takes a base URL + a decimal amount and returns a clickable
/// URL. Encapsulating it here also means the unit tests can lock the
/// escaping contract without instantiating an `Invoice` mock.
public enum InvoiceStripeLinkBuilder {

    /// Appends `prefilled_amount=<cents>` to `base`, preserving any
    /// existing query parameters and gracefully degrading when the
    /// base is empty / malformed.
    ///
    /// - Parameters:
    ///   - base: The Stripe Payment Link URL prefix the user pasted
    ///           into Settings, e.g. `https://buy.stripe.com/3cs5ll…`.
    ///   - amountEUR: The pre-tax + VAT total to pre-fill. Negative
    ///                amounts collapse to 0 — the data layer should
    ///                have caught this already, but the URL builder
    ///                stays defensive.
    /// - Returns: A `String` URL that the customer can open. `nil`
    ///            when `base` is empty / unrecognisable as a URL.
    public static func appendAmount(
        base: String,
        amountEUR: Double
    ) -> String? {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard var components = URLComponents(string: trimmed) else { return nil }

        // Stripe wants the integer number of cents — multiply by 100,
        // round half-to-even, never go below zero. Doing the rounding
        // in Double space then casting to Int keeps us inside the safe
        // range for any realistic invoice (< 1 trillion cents).
        let cents = max(0, Int((amountEUR * 100.0).rounded()))

        var items = components.queryItems ?? []
        // Drop any pre-existing `prefilled_amount` so re-issuing the
        // link with a fresh amount doesn't end up with the parameter
        // appearing twice (Stripe takes the last one but it's wasteful
        // and confusing if the user manually inspects the URL).
        items.removeAll { $0.name == "prefilled_amount" }
        items.append(URLQueryItem(name: "prefilled_amount", value: "\(cents)"))
        components.queryItems = items

        return components.url?.absoluteString
    }

    /// Convenience: builds the link for a fully-materialised `Invoice`
    /// using its `amountTTC` (the figure the customer actually pays).
    /// Returns `nil` when `base` is empty so the InvoiceSheet can
    /// branch on optional binding to hide the Stripe block when the
    /// preference isn't configured yet.
    public static func appendAmount(
        base: String,
        for invoice: Invoice
    ) -> String? {
        appendAmount(base: base, amountEUR: invoice.amountTTC)
    }
}
