import Foundation

/// Inversion point between the AuditController (here in AuditKit) and
/// the VisualKit module that owns the GPT Image 2 generator.
///
/// Defined here — not in VisualKit — so the AuditController can take a
/// strongly-typed dependency without AuditKit having to import
/// VisualKit (which would create a circular module graph). VisualKit
/// ships a `RedesignMockupSourceAdapter` that conforms its generator
/// to this protocol.
///
/// When `mockupSource` is nil on the controller (no OpenAI key
/// configured, or unit tests), the post-synthesis kickoff is skipped
/// entirely — zero overhead. When non-nil, the controller kicks off a
/// detached task after the synthesised report lands; the task awaits
/// the generator and, when results arrive, the controller appends
/// them onto `report.mockups` for the UI to observe.
public protocol RedesignMockupSource: Sendable {
    /// Generate up to 3 "after redesign" mockups for the given audit
    /// report. The adapter is free to soft-fail per mockup and return
    /// a shorter array — the controller will still surface what
    /// landed. Throws only on hard, terminal errors (missing API key
    /// is the canonical one) so the caller can hide the section
    /// rather than show an empty carousel.
    func generate(for report: AuditReport) async throws -> [RedesignMockup]
}
