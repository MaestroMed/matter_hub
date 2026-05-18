import Foundation

/// One generated visual concept (logo, homepage, lifestyle photo, app
/// screen). Designed to be cheap to serialize so we can persist the
/// board manifest as JSON in the App Group filesystem and ship the
/// images themselves as siblings to the manifest.
public struct VisualConcept: Sendable, Codable, Hashable, Identifiable {
    public let id: UUID
    public let kind: Kind
    public let variant: Int               // 1, 2, 3, …
    public let prompt: String              // the actual prompt sent to OpenAI
    public let filename: String            // basename on disk, e.g. "logo-1.png"
    public let createdAt: Date

    public enum Kind: String, Sendable, Codable, CaseIterable {
        case logo
        case homepage
        case lifestyle
        case appScreen

        public var displayName: String {
            switch self {
            case .logo:      return "Logo"
            case .homepage:  return "Homepage"
            case .lifestyle: return "Photo lifestyle"
            case .appScreen: return "App mobile"
            }
        }

        /// Square 1024 for logos & app screens, landscape for homepages,
        /// landscape for lifestyle photography too.
        public var preferredSize: VisualSize {
            switch self {
            case .logo, .appScreen: return .square
            case .homepage, .lifestyle: return .landscape
            }
        }
    }

    public init(
        id: UUID = UUID(),
        kind: Kind,
        variant: Int,
        prompt: String,
        filename: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.kind = kind
        self.variant = variant
        self.prompt = prompt
        self.filename = filename
        self.createdAt = createdAt
    }
}

public enum VisualSize: String, Sendable, Codable {
    case square          // 1024 × 1024
    case landscape       // 1536 × 1024
    case portrait        // 1024 × 1536

    public var dimensions: (width: Int, height: Int) {
        switch self {
        case .square:    return (1024, 1024)
        case .landscape: return (1536, 1024)
        case .portrait:  return (1024, 1536)
        }
    }

    public var openAIValue: String {
        switch self {
        case .square:    return "1024x1024"
        case .landscape: return "1536x1024"
        case .portrait:  return "1024x1536"
        }
    }
}

/// Persisted manifest describing the full set of concepts generated for
/// a given client Node. Stored as `manifest.json` next to the PNGs in
/// the App Group container.
public struct VisualBoardManifest: Sendable, Codable, Hashable {
    /// Stable per-prospect key derived from the audited URL (host).
    /// Lets us look up the same board across audit runs without needing
    /// to thread a Node SwiftData id around.
    public var clientKey: String
    public var clientName: String
    public var generatedAt: Date
    public var concepts: [VisualConcept]
    public var qualityUsed: OpenAIImageQuality
    public var totalCostEUR: Double?       // best-effort estimate

    public init(
        clientKey: String,
        clientName: String,
        generatedAt: Date = .now,
        concepts: [VisualConcept],
        qualityUsed: OpenAIImageQuality,
        totalCostEUR: Double? = nil
    ) {
        self.clientKey = clientKey
        self.clientName = clientName
        self.generatedAt = generatedAt
        self.concepts = concepts
        self.qualityUsed = qualityUsed
        self.totalCostEUR = totalCostEUR
    }

    /// Concepts of a given kind, sorted by variant ascending. Drives the
    /// horizontal scrollers inside VisualBoardView.
    public func concepts(of kind: VisualConcept.Kind) -> [VisualConcept] {
        concepts
            .filter { $0.kind == kind }
            .sorted { $0.variant < $1.variant }
    }
}

public enum VisualBoardKey {
    /// Stable string derived from a URL: `https://www.stripe.com/` and
    /// `stripe.com` both collapse to `"stripe.com"`. Used as the
    /// filesystem subfolder name + manifest clientKey.
    public static func key(for url: URL) -> String {
        let host = url.host(percentEncoded: false)?.lowercased() ?? url.absoluteString.lowercased()
        let cleaned = host.replacingOccurrences(of: "www.", with: "")
        return cleaned.replacingOccurrences(of: "[^a-z0-9.-]", with: "_", options: .regularExpression)
    }
}

public enum OpenAIImageQuality: String, Sendable, Codable, CaseIterable {
    case low
    case medium
    case high

    public var displayName: String {
        switch self {
        case .low:    return "Low (rapide)"
        case .medium: return "Medium (équilibré)"
        case .high:   return "High (SOTA)"
        }
    }

    /// Indicative cost per 1024×1024 image in EUR, sourced from the
    /// May 2026 GPT Image 2 pricing grid. Used for the budget estimate
    /// shown to the user before launching a generation.
    public var indicativeCostPerImageEUR: Double {
        switch self {
        case .low:    return 0.006
        case .medium: return 0.049
        case .high:   return 0.195
        }
    }
}
