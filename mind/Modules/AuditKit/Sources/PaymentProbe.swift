import Foundation

/// Detects payment processors and pay-wall presence — signals whether
/// the prospect has a monetisation flow live, and what stack runs it.
public enum PaymentProbe {
    private static let processors: [(needle: String, label: String)] = [
        ("js.stripe.com",           "Stripe"),
        ("checkout.stripe.com",     "Stripe"),
        ("pk_live_",                "Stripe (publishable key in markup)"),
        ("paddle.com",              "Paddle"),
        ("lemonsqueezy.com",        "Lemon Squeezy"),
        ("gocardless",              "GoCardless"),
        ("braintreepayments.com",   "Braintree"),
        ("squarespace.com",         "Square"),
        ("paypal.com/sdk",          "PayPal"),
        ("klarna.com",              "Klarna"),
        ("alma-eu",                 "Alma"),
        ("scalapay",                "Scalapay"),
        ("oneylink",                "Oney"),
        ("shop.app",                "Shopify Shop Pay"),
        ("snipcart",                "Snipcart"),
        ("chargebee",               "Chargebee"),
        ("recurly",                 "Recurly"),
    ]

    private static let payWallHints = [
        "/pricing", "/plans", "/tarifs", "/prix", "/abonnement", "/subscribe",
        "data-price", "stripe-element", "checkout-button"
    ]

    public static func fetch(for url: URL) async throws -> PaymentFindings {
        let html = try await HTMLProbe.fetchLowercased(url)

        var detected = Set<String>()
        for entry in processors where html.contains(entry.needle) {
            detected.insert(entry.label)
        }
        let hasPayWall = payWallHints.contains { html.contains($0) }

        return PaymentFindings(
            processors: Array(detected).sorted(),
            hasPayWall: hasPayWall
        )
    }
}
