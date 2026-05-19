import UIKit
import Social
import UniformTypeIdentifiers
import GraphCore

/// Hosts the system Share UI when the user picks "MIND" from any
/// app's share sheet (Safari, Mail, Notes, Messages, Photos…).
///
/// Design choices
/// --------------
/// - We use SLComposeServiceViewController instead of a custom view so
///   iOS gives us the native "compose with comment + Cancel / Post"
///   chrome for free. The user can add a comment before posting.
/// - We do NOT open SwiftData here — the extension's memory budget is
///   tight and CloudKit init alone can take 500ms+. Instead we serialize
///   the URL + comment to `ShareInbox` and let the host app drain on
///   next foreground. Worst case (host opened > 24h later), the iCloud
///   mirror picks up the file via the App Group sync.
/// - Single-item input: NSExtensionActivationRule limits us to one
///   web URL or one text item per invocation. Multi-select is a v2.
@objc(ShareViewController)
final class ShareViewController: SLComposeServiceViewController {

    /// Title shown above the compose box. Localised in FR per Mehdi
    /// convention (the app's UI strings are FR-first).
    override func loadView() {
        super.loadView()
        self.placeholder = "Ajoute un commentaire…"
        self.title = "MIND"
    }

    /// Validates the user can post. Always true for now — the extension
    /// accepts an empty comment (the shared URL alone is enough to
    /// create a capture) or a pure text share with no URL.
    override func isContentValid() -> Bool {
        return true
    }

    /// Called when the user taps "Post". Serializes the shared data
    /// into the cross-process ShareInbox queue and immediately tells
    /// iOS we're done so the share sheet animates out smoothly.
    override func didSelectPost() {
        let comment = self.contentText ?? ""

        // Extension contexts can carry multiple input items (e.g.
        // sharing 3 photos at once), but our activation rule restricts
        // us to one — still, defensive iteration so a stray multi-item
        // input doesn't crash.
        let items: [NSExtensionItem] = (self.extensionContext?.inputItems ?? [])
            .compactMap { $0 as? NSExtensionItem }

        Task {
            let urls = await collectURLs(from: items)
            let texts = await collectText(from: items)

            // Stitch the user's free-text comment onto whatever the
            // host app surfaced (e.g. Safari posts a URL + the page
            // title as plain text — both go into the body).
            let combinedText = stitchText(comment: comment, sharedTexts: texts)

            let payload = ShareInbox.Payload(
                url: urls.first,
                text: combinedText.isEmpty ? nil : combinedText
            )
            _ = ShareInbox.enqueue(payload)

            await MainActor.run {
                self.extensionContext?.completeRequest(
                    returningItems: [],
                    completionHandler: nil
                )
            }
        }
    }

    /// Sibling of `didSelectPost` — called when the user taps Cancel.
    /// Default base-class behaviour cancels the request; we override to
    /// avoid leaving anything in the queue.
    override func didSelectCancel() {
        self.extensionContext?.cancelRequest(
            withError: NSError(
                domain: "app.mind.ios.shareextension",
                code: NSUserCancelledError
            )
        )
    }

    /// We don't surface configuration options for now (no "post to
    /// which graph", no "kind picker") so the base class is told there
    /// are no rows.
    override func configurationItems() -> [Any]! {
        return []
    }

    // MARK: - NSItemProvider extraction

    /// Pulls every URL the host app exposed, in order. SLComposeService
    /// hands us NSItemProviders; we ask each for `URL.self` and unwrap
    /// the casted result on the main actor for safety.
    private func collectURLs(from items: [NSExtensionItem]) async -> [URL] {
        var result: [URL] = []
        for item in items {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let url = await loadURL(provider, identifier: UTType.url.identifier) {
                        result.append(url)
                    }
                }
            }
        }
        return result
    }

    /// Pulls plain text the host app exposed. Safari typically posts a
    /// `public.url` AND a `public.plain-text` carrying the page title.
    private func collectText(from items: [NSExtensionItem]) async -> [String] {
        var result: [String] = []
        for item in items {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let text = await loadString(provider, identifier: UTType.plainText.identifier) {
                        result.append(text)
                    }
                }
            }
        }
        return result
    }

    /// Bridges the legacy completion-handler `NSItemProvider` API into
    /// async/await, narrowing the loaded value to `URL?` so the
    /// continuation only ever carries a Sendable payload — required by
    /// Swift 6 strict concurrency. Falls back to `URL(string:)` when
    /// the host app posts a URL as a plain string.
    private func loadURL(_ provider: NSItemProvider, identifier: String) async -> URL? {
        await withCheckedContinuation { (continuation: CheckedContinuation<URL?, Never>) in
            provider.loadItem(forTypeIdentifier: identifier, options: nil) { value, _ in
                if let url = value as? URL {
                    continuation.resume(returning: url)
                } else if let str = value as? String, let url = URL(string: str) {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// Sibling helper for the `public.plain-text` case. Same Sendable
    /// narrowing as `loadURL` — we only ever resume the continuation
    /// with a Sendable value (`String?`).
    private func loadString(_ provider: NSItemProvider, identifier: String) async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            provider.loadItem(forTypeIdentifier: identifier, options: nil) { value, _ in
                if let str = value as? String {
                    continuation.resume(returning: str)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// Combine the user-typed comment with the host-provided text so a
    /// Safari "share with comment" post produces a body that contains
    /// both pieces of information. We keep them on separate paragraphs
    /// so the MarkdownView in the host app can render them cleanly.
    private func stitchText(comment: String, sharedTexts: [String]) -> String {
        var parts: [String] = []
        let trimmedComment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedComment.isEmpty { parts.append(trimmedComment) }
        for text in sharedTexts {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            // Drop the shared text if it duplicates the user comment
            // (avoids "Stripe pricing\n\nStripe pricing" when the user
            // shares the page they're commenting on).
            if !trimmed.isEmpty, trimmed != trimmedComment {
                parts.append(trimmed)
            }
        }
        return parts.joined(separator: "\n\n")
    }
}
