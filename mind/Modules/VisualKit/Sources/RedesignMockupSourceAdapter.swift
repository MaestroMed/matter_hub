import Foundation
import AuditKit

/// Concrete `RedesignMockupSource` that delegates to
/// `RedesignMockupGenerator`. Lives in VisualKit (which already
/// depends on AuditKit) so the AuditController can plug in via the
/// `RedesignMockupSource` protocol declared in AuditKit without
/// AuditKit having to know about GPT Image 2 or the OpenAI Keychain.
///
/// Defaults to `OpenAIImageQuality.medium` per the v0.23 spec —
/// `.high` is exposed as opt-in via the initializer for a future
/// Settings toggle.
public struct RedesignMockupSourceAdapter: RedesignMockupSource {
    private let generator: RedesignMockupGenerator
    private let quality: OpenAIImageQuality

    public init(
        generator: RedesignMockupGenerator = .shared,
        quality: OpenAIImageQuality = .medium
    ) {
        self.generator = generator
        self.quality = quality
    }

    public func generate(for report: AuditReport) async throws -> [RedesignMockup] {
        let host = report.client.url.host(percentEncoded: false)
            ?? report.client.url.absoluteString
        let name = report.client.displayName
        return try await generator.generate(
            siteScreenshotPNG: nil,
            clientName: name,
            host: host,
            top3QuickWins: report.quickWins,
            persona: report.persona,
            quality: quality
        )
    }
}
