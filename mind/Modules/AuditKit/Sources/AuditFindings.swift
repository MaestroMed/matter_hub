import Foundation

/// Structured measurements collected by the audit probes, in addition to
/// PageSpeed (which lives in AuditReport.PerformanceMetrics). Each section
/// is optional so a flaky probe can soft-fail without taking the rest down.
public struct AuditFindings: Sendable, Codable, Hashable {
    public var security: SecurityFindings?
    public var email: EmailFindings?
    public var domain: DomainFindings?
    public var mobile: MobileFindings?

    // BLOC B extended findings — second-wave probes.
    public var schema: SchemaFindings?
    public var openGraph: OpenGraphFindings?
    public var crawlability: CrawlabilityFindings?
    public var compliance: ComplianceFindings?
    public var analytics: AnalyticsFindings?
    public var payment: PaymentFindings?
    public var cdn: CDNFindings?
    public var trust: TrustFindings?

    public init(
        security: SecurityFindings? = nil,
        email: EmailFindings? = nil,
        domain: DomainFindings? = nil,
        mobile: MobileFindings? = nil,
        schema: SchemaFindings? = nil,
        openGraph: OpenGraphFindings? = nil,
        crawlability: CrawlabilityFindings? = nil,
        compliance: ComplianceFindings? = nil,
        analytics: AnalyticsFindings? = nil,
        payment: PaymentFindings? = nil,
        cdn: CDNFindings? = nil,
        trust: TrustFindings? = nil
    ) {
        self.security = security
        self.email = email
        self.domain = domain
        self.mobile = mobile
        self.schema = schema
        self.openGraph = openGraph
        self.crawlability = crawlability
        self.compliance = compliance
        self.analytics = analytics
        self.payment = payment
        self.cdn = cdn
        self.trust = trust
    }

    /// True if at least one probe contributed something. Used by the prompt
    /// builder to decide whether to embed a findings block at all.
    public var hasAnyData: Bool {
        security != nil || email != nil || domain != nil || mobile != nil
            || schema != nil || openGraph != nil || crawlability != nil
            || compliance != nil || analytics != nil || payment != nil
            || cdn != nil || trust != nil
    }
}

public struct SecurityFindings: Sendable, Codable, Hashable {
    public let grade: String              // "A+" / "A" / "B" / "C" / "D" / "F"
    public let score: Int                 // 0–100, raw weighted total
    public let presentHeaders: [String]
    public let missingHeaders: [String]
    public let tlsValid: Bool

    public init(
        grade: String,
        score: Int,
        presentHeaders: [String],
        missingHeaders: [String],
        tlsValid: Bool
    ) {
        self.grade = grade
        self.score = score
        self.presentHeaders = presentHeaders
        self.missingHeaders = missingHeaders
        self.tlsValid = tlsValid
    }
}

public struct EmailFindings: Sendable, Codable, Hashable {
    public let provider: String?          // "Google Workspace" / "Microsoft 365" / "Brevo" / nil
    public let mxHosts: [String]
    public let hasSPF: Bool
    public let hasDMARC: Bool

    public init(
        provider: String?,
        mxHosts: [String],
        hasSPF: Bool,
        hasDMARC: Bool
    ) {
        self.provider = provider
        self.mxHosts = mxHosts
        self.hasSPF = hasSPF
        self.hasDMARC = hasDMARC
    }
}

public struct DomainFindings: Sendable, Codable, Hashable {
    public let registrar: String?
    public let createdAt: Date?
    public let ageYears: Double?

    public init(registrar: String?, createdAt: Date?, ageYears: Double?) {
        self.registrar = registrar
        self.createdAt = createdAt
        self.ageYears = ageYears
    }
}

public struct MobileFindings: Sendable, Codable, Hashable {
    public let hasIOSApp: Bool
    public let appName: String?
    public let sellerName: String?
    public let averageRating: Double?
    public let ratingCount: Int?
    public let primaryGenre: String?

    public init(
        hasIOSApp: Bool,
        appName: String? = nil,
        sellerName: String? = nil,
        averageRating: Double? = nil,
        ratingCount: Int? = nil,
        primaryGenre: String? = nil
    ) {
        self.hasIOSApp = hasIOSApp
        self.appName = appName
        self.sellerName = sellerName
        self.averageRating = averageRating
        self.ratingCount = ratingCount
        self.primaryGenre = primaryGenre
    }
}

// MARK: - BLOC B extended findings

public struct SchemaFindings: Sendable, Codable, Hashable {
    public let hasJSONLD: Bool
    public let detectedTypes: [String]      // ["Organization", "Product", "FAQPage"]

    public init(hasJSONLD: Bool, detectedTypes: [String]) {
        self.hasJSONLD = hasJSONLD
        self.detectedTypes = detectedTypes
    }
}

public struct OpenGraphFindings: Sendable, Codable, Hashable {
    public let hasTitle: Bool
    public let hasDescription: Bool
    public let hasImage: Bool
    public let hasType: Bool
    public let hasTwitterCard: Bool
    public let completenessScore: Int       // 0–100

    public init(
        hasTitle: Bool,
        hasDescription: Bool,
        hasImage: Bool,
        hasType: Bool,
        hasTwitterCard: Bool,
        completenessScore: Int
    ) {
        self.hasTitle = hasTitle
        self.hasDescription = hasDescription
        self.hasImage = hasImage
        self.hasType = hasType
        self.hasTwitterCard = hasTwitterCard
        self.completenessScore = completenessScore
    }
}

public struct CrawlabilityFindings: Sendable, Codable, Hashable {
    public let hasRobotsTxt: Bool
    public let allowsAllCrawlers: Bool
    public let hasSitemap: Bool
    public let sitemapURLCount: Int?

    public init(
        hasRobotsTxt: Bool,
        allowsAllCrawlers: Bool,
        hasSitemap: Bool,
        sitemapURLCount: Int? = nil
    ) {
        self.hasRobotsTxt = hasRobotsTxt
        self.allowsAllCrawlers = allowsAllCrawlers
        self.hasSitemap = hasSitemap
        self.sitemapURLCount = sitemapURLCount
    }
}

public struct ComplianceFindings: Sendable, Codable, Hashable {
    public let hasCookieBanner: Bool
    public let cookieProvider: String?      // "Cookiebot", "Axeptio", "Didomi", "OneTrust", "tarteaucitron", or nil
    public let hasPrivacyLink: Bool         // detected /privacy /confidentialite link
    public let hasTermsLink: Bool

    public init(
        hasCookieBanner: Bool,
        cookieProvider: String?,
        hasPrivacyLink: Bool,
        hasTermsLink: Bool
    ) {
        self.hasCookieBanner = hasCookieBanner
        self.cookieProvider = cookieProvider
        self.hasPrivacyLink = hasPrivacyLink
        self.hasTermsLink = hasTermsLink
    }
}

public struct AnalyticsFindings: Sendable, Codable, Hashable {
    public let providers: [String]          // ["Google Analytics 4", "Plausible", "Mixpanel", ...]
    public let hasErrorTracking: Bool       // Sentry / Bugsnag detected

    public var hasAnyAnalytics: Bool { !providers.isEmpty }

    public init(providers: [String], hasErrorTracking: Bool) {
        self.providers = providers
        self.hasErrorTracking = hasErrorTracking
    }
}

public struct PaymentFindings: Sendable, Codable, Hashable {
    public let processors: [String]         // ["Stripe", "Lemon Squeezy", "Paddle", "PayPal", "GoCardless"]
    public let hasPayWall: Bool             // pricing page detected

    public var hasMonetization: Bool { !processors.isEmpty || hasPayWall }

    public init(processors: [String], hasPayWall: Bool) {
        self.processors = processors
        self.hasPayWall = hasPayWall
    }
}

public struct CDNFindings: Sendable, Codable, Hashable {
    public let provider: String?            // "Cloudflare", "Fastly", "Vercel", "Netlify", "AWS CloudFront", nil
    public let serverHeader: String?

    public init(provider: String?, serverHeader: String?) {
        self.provider = provider
        self.serverHeader = serverHeader
    }
}

public struct TrustFindings: Sendable, Codable, Hashable {
    public let trustpilotScore: Double?     // 0.0–5.0
    public let trustpilotReviewCount: Int?
    public let trustpilotProfileURL: URL?

    public init(
        trustpilotScore: Double?,
        trustpilotReviewCount: Int?,
        trustpilotProfileURL: URL?
    ) {
        self.trustpilotScore = trustpilotScore
        self.trustpilotReviewCount = trustpilotReviewCount
        self.trustpilotProfileURL = trustpilotProfileURL
    }
}
