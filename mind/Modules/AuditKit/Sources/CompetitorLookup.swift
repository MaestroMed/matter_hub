import Foundation

/// v0.24 — Audit Battle Mode competitor lookup.
///
/// Pure value-type table that maps a SaaS host to a short list of
/// hand-curated direct competitors. Used by `BattleSheet` to pre-fill
/// the "competitors" chips when Mehdi types a primary URL — one tap
/// auto-populates the battlefield with three rivals worth comparing
/// the prospect against.
///
/// Why a hardcoded table
/// ---------------------
/// Real competitor inference would need an LLM call + a brand graph
/// + a fuzzy-match across the prospect's segment. That's a future
/// version. For now the table covers the 20-something SaaS verticals
/// Mehdi sees most often (payments, project mgmt, design, hosting,
/// dev tools, analytics, CRM, etc.) — every entry was vetted by hand
/// so the "auto-suggest" experience feels intentional rather than
/// generic. The UI lets Mehdi edit/add/remove chips, so an unknown
/// host or a missing competitor never blocks the flow.
public enum CompetitorLookup {

    /// Maps a normalised host (lowercase, no `www.` prefix) to a
    /// short list of 2-4 direct competitor hosts. Entries are
    /// alphabetised by key so a future audit can use `git diff` to
    /// surface what changed between versions of the table.
    ///
    /// Curated for v0.24. Mehdi can extend this in place when a new
    /// vertical lands in his pipeline — no other code change is
    /// needed (the SwiftUI form reads the table directly).
    public static let table: [String: [String]] = [
        // Payments / billing
        "stripe.com":       ["adyen.com", "mollie.com", "checkout.com"],
        "adyen.com":        ["stripe.com", "checkout.com", "braintreepayments.com"],
        "mollie.com":       ["stripe.com", "adyen.com", "gocardless.com"],
        "paddle.com":       ["lemonsqueezy.com", "chargebee.com", "fastspring.com"],
        "lemonsqueezy.com": ["paddle.com", "gumroad.com", "chargebee.com"],

        // Project management / issue tracking
        "linear.app":       ["jira.com", "shortcut.com", "height.app"],
        "shortcut.com":     ["linear.app", "jira.com", "height.app"],
        "height.app":       ["linear.app", "shortcut.com", "jira.com"],
        "asana.com":        ["monday.com", "clickup.com", "trello.com"],
        "monday.com":       ["asana.com", "clickup.com", "smartsheet.com"],
        "clickup.com":      ["asana.com", "monday.com", "notion.so"],

        // Notes / knowledge / docs
        "notion.so":        ["coda.io", "obsidian.md", "craft.do"],
        "coda.io":          ["notion.so", "airtable.com", "clickup.com"],
        "obsidian.md":      ["notion.so", "craft.do", "logseq.com"],
        "craft.do":         ["notion.so", "obsidian.md", "bear.app"],

        // Hosting / deployment
        "vercel.com":       ["netlify.com", "render.com", "fly.io"],
        "netlify.com":      ["vercel.com", "render.com", "cloudflare.com"],
        "render.com":       ["vercel.com", "netlify.com", "fly.io"],
        "fly.io":           ["render.com", "vercel.com", "railway.app"],
        "railway.app":      ["fly.io", "render.com", "heroku.com"],

        // Design tools
        "figma.com":        ["sketch.com", "framer.com", "lunacy.app"],
        "framer.com":       ["webflow.com", "figma.com", "wix.com"],
        "webflow.com":      ["framer.com", "wix.com", "squarespace.com"],

        // Backend / database / dev infra
        "supabase.com":     ["firebase.google.com", "planetscale.com", "neon.tech"],
        "planetscale.com":  ["neon.tech", "supabase.com", "cockroachlabs.com"],
        "neon.tech":        ["planetscale.com", "supabase.com", "cockroachlabs.com"],

        // CRM / sales
        "hubspot.com":      ["salesforce.com", "pipedrive.com", "attio.com"],
        "attio.com":        ["hubspot.com", "pipedrive.com", "salesforce.com"],
        "pipedrive.com":    ["hubspot.com", "attio.com", "salesforce.com"],

        // Analytics
        "mixpanel.com":     ["amplitude.com", "posthog.com", "heap.io"],
        "amplitude.com":    ["mixpanel.com", "posthog.com", "heap.io"],
        "posthog.com":      ["mixpanel.com", "amplitude.com", "heap.io"],

        // Email marketing
        "mailchimp.com":    ["brevo.com", "klaviyo.com", "convertkit.com"],
        "klaviyo.com":      ["mailchimp.com", "brevo.com", "activecampaign.com"],

        // Customer support
        "intercom.com":     ["zendesk.com", "crisp.chat", "front.com"],
        "zendesk.com":      ["intercom.com", "freshdesk.com", "front.com"],
    ]

    /// Returns 0-3 competitor hosts for `host`, normalised to lower-
    /// case and `www.`-stripped before lookup. Unknown hosts return
    /// an empty array — the UI then keeps the chips list empty and
    /// Mehdi can type competitors manually.
    ///
    /// Pure, total, deterministic: every call with the same input
    /// returns the same output and never throws.
    public static func competitors(for host: String) -> [String] {
        table[normalise(host)] ?? []
    }

    /// Returns the canonical key shape used by `table`: lowercase,
    /// trimmed, with the `www.` prefix removed. Exposed so the UI
    /// (and tests) can match on the same string the lookup uses.
    public static func normalise(_ host: String) -> String {
        var lowered = host.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if lowered.hasPrefix("www.") {
            lowered.removeFirst(4)
        }
        return lowered
    }
}
