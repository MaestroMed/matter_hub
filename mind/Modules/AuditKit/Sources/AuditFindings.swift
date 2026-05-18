import Foundation

/// Structured measurements collected by the audit probes, in addition to
/// PageSpeed (which lives in AuditReport.PerformanceMetrics). Each section
/// is optional so a flaky probe can soft-fail without taking the rest down.
public struct AuditFindings: Sendable, Codable, Hashable {
    public var security: SecurityFindings?
    public var email: EmailFindings?
    public var domain: DomainFindings?
    public var mobile: MobileFindings?

    public init(
        security: SecurityFindings? = nil,
        email: EmailFindings? = nil,
        domain: DomainFindings? = nil,
        mobile: MobileFindings? = nil
    ) {
        self.security = security
        self.email = email
        self.domain = domain
        self.mobile = mobile
    }

    /// True if at least one probe contributed something. Used by the prompt
    /// builder to decide whether to embed a findings block at all.
    public var hasAnyData: Bool {
        security != nil || email != nil || domain != nil || mobile != nil
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
