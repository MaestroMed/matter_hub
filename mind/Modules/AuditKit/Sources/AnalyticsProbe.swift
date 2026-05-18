import Foundation

/// Detects analytics + error-tracking SDKs embedded in the home page.
/// Signals the maturity of the prospect's data culture.
public enum AnalyticsProbe {
    private static let analytics: [(needle: String, label: String)] = [
        ("googletagmanager.com",        "Google Tag Manager"),
        ("google-analytics.com",        "Google Analytics 4"),
        ("gtag(",                       "Google Analytics 4"),
        ("ga('create'",                 "Universal Analytics (legacy)"),
        ("plausible.io",                "Plausible"),
        ("data-domain=",                "Plausible"),
        ("simpleanalytics",             "Simple Analytics"),
        ("mixpanel",                    "Mixpanel"),
        ("amplitude",                   "Amplitude"),
        ("posthog",                     "PostHog"),
        ("segment.com",                 "Segment"),
        ("matomo",                      "Matomo"),
        ("piwik",                       "Matomo (legacy)"),
        ("hotjar.com",                  "Hotjar"),
        ("static.ads-twitter.com",      "Twitter Pixel"),
        ("connect.facebook.net",        "Meta Pixel"),
        ("snap.licdn.com",              "LinkedIn Insight Tag"),
        ("clarity.ms",                  "Microsoft Clarity"),
        ("fullstory.com",               "FullStory"),
        ("heap.io",                     "Heap"),
        ("split.io",                    "Split.io"),
    ]

    private static let errorTracking: [(needle: String, label: String)] = [
        ("sentry.io",       "Sentry"),
        ("bugsnag",         "Bugsnag"),
        ("rollbar",         "Rollbar"),
        ("raygun",          "Raygun"),
        ("datadog-rum",     "Datadog RUM"),
        ("newrelic",        "New Relic Browser"),
    ]

    public static func fetch(for url: URL) async throws -> AnalyticsFindings {
        let html = try await HTMLProbe.fetchLowercased(url)

        var detected = Set<String>()
        for entry in analytics where html.contains(entry.needle) {
            detected.insert(entry.label)
        }
        let hasErrorTracking = errorTracking.contains { html.contains($0.needle) }

        return AnalyticsFindings(
            providers: Array(detected).sorted(),
            hasErrorTracking: hasErrorTracking
        )
    }
}
