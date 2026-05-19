import Foundation

/// Lightweight value handle the App layer passes from AuditSheet into
/// `AuditController.run(for:liveBroadcaster:)`. Hides the writer's
/// folder layout from the call sites — they only need the token, the
/// folder URL, and a stable "where do I tell the user to point their
/// browser" suggestion.
///
/// The session does NOT own the writer. The writer is the singleton
/// actor `LiveBroadcastWriter.shared`. The session is the
/// per-broadcast metadata bundle.
public struct LiveBroadcastSession: Sendable, Hashable, Identifiable {

    /// 32-char lowercase hex slug. Matches the `LiveBroadcastState.token`
    /// at the head of the on-disk JSON.
    public let token: String

    /// Absolute URL of the on-disk folder hosting `index.html` +
    /// `state.json`. Mehdi can `cd` into this path in Terminal and run
    /// `npx serve` to expose the broadcast over localhost, then route
    /// it through `cloudflared tunnel --url http://localhost:3000` to
    /// hand a public URL to the client.
    public let folderURL: URL

    /// Suggested shareable URL pattern. Empty out of the box (the
    /// writer doesn't know what tunneling layer Mehdi will pick) but
    /// the AuditSheet plugs in `file://…/<token>/index.html` so the
    /// initial QR / copy-link CTA is never empty.
    public let suggestedURL: URL

    /// Same as `token` so SwiftUI's `Identifiable` collections (sheets,
    /// `ForEach`) work without a wrapper.
    public var id: String { token }

    public init(
        token: String,
        folderURL: URL,
        suggestedURL: URL
    ) {
        self.token = token
        self.folderURL = folderURL
        self.suggestedURL = suggestedURL
    }
}
