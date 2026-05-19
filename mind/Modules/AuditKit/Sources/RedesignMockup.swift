import Foundation

/// One "after redesign" mockup rendered by GPT Image 2 from the brief
/// of a single quick win. Stored on `AuditReport.mockups` so the
/// AuditSheet + the Client Portal HTML can render the same set
/// without re-querying the upstream API.
///
/// Lives in AuditKit (rather than VisualKit, where the HTTP generator
/// lives) so `AuditReport` can hold an array of them without dragging
/// VisualKit's UIKit / Observable surface into every consumer. The
/// pure prompt builder + the `RedesignMockupGenerator` actor stay in
/// VisualKit, which already depends on AuditKit — the dependency
/// graph flows in one direction.
///
/// `imageData` is raw PNG bytes — every consumer (SwiftUI `Image`,
/// portal HTML base64 embed, optional disk persistence) reads from
/// the same `Data` payload. Codable so the report can round-trip
/// through the same SwiftData persistence path as the rest of the
/// audit. The byte cost is acceptable: a 16:9 medium-quality GPT
/// Image 2 PNG averages 140–220 KB, three of them ≈ 0.5 MB, well
/// inside the CloudKit per-record envelope.
public struct RedesignMockup: Sendable, Codable, Hashable, Identifiable {
    public let id: UUID
    /// Short, French, title for the carousel caption. Derived from
    /// the originating quick-win title by the prompt builder.
    public let title: String
    /// Verbatim quick-win title — surfaced under the mockup in both
    /// the AuditSheet carousel + the portal gallery so the prospect
    /// can immediately tie the visual to the recommendation.
    public let quickWinTitle: String
    /// Optional verbose description of the quick win, used by the
    /// full-screen modal in the AuditSheet.
    public let quickWinDetail: String
    /// Raw PNG bytes. Always present — a failed generation never
    /// produces a `RedesignMockup`, the soft-fail branch in the
    /// generator simply omits it from the returned array.
    public let imageData: Data
    /// Exact prompt sent to GPT Image 2. Kept inside the value type
    /// so a future "regenerate this tile" CTA can be wired without
    /// re-running the prompt builder.
    public let prompt: String

    public init(
        id: UUID = UUID(),
        title: String,
        quickWinTitle: String,
        quickWinDetail: String,
        imageData: Data,
        prompt: String
    ) {
        self.id = id
        self.title = title
        self.quickWinTitle = quickWinTitle
        self.quickWinDetail = quickWinDetail
        self.imageData = imageData
        self.prompt = prompt
    }
}
