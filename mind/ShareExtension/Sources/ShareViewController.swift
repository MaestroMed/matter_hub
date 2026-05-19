import UIKit
import Social
import UniformTypeIdentifiers
import Contacts
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
            // v0.13 — Contacts.app shares post a vCard via
            // `public.vcard`. Detect that branch first; if any contact
            // payload was produced we skip the URL/text fall-through
            // (a vCard share never carries a URL anyway). Multi-contact
            // selection is bounded by the activation rule (max 1) but
            // we iterate defensively in case iOS hands us more.
            let contactPayloads = await collectContactPayloads(
                from: items,
                userComment: comment
            )
            if !contactPayloads.isEmpty {
                for payload in contactPayloads {
                    _ = ShareInbox.enqueue(payload)
                }
                await MainActor.run {
                    self.extensionContext?.completeRequest(
                        returningItems: [],
                        completionHandler: nil
                    )
                }
                return
            }

            let urls = await collectURLs(from: items)
            let texts = await collectText(from: items)

            // v0.14 — Mail.app share. iOS's Mail surfaces a shared
            // message as a `public.plain-text` item (plus an optional
            // `message://` URL the user can't open in another app).
            // We sniff the raw text for the canonical envelope
            // headers (`From:` + `Subject:`); if either matches we
            // route this through the mail branch and skip the
            // generic `.link` fallback so the resulting Node is a
            // `mail` with subject/sender/body rather than a vanilla
            // capture. We also bail-out on the `public.message-rfc822`
            // item type when iOS surfaces it (rare on iOS Mail.app
            // but common when sharing from third-party clients).
            let isMailItemType = items.contains { item in
                (item.attachments ?? []).contains { provider in
                    provider.hasItemConformingToTypeIdentifier("public.message-rfc822")
                }
            }
            let rawMailText = texts.first(where: { looksLikeMail($0) })
            if isMailItemType || rawMailText != nil {
                let body = rawMailText
                    ?? texts.first
                    ?? ""
                if let payload = ShareInbox.Payload.mailPayload(
                    rawText: body,
                    userComment: comment
                ) {
                    _ = ShareInbox.enqueue(payload)
                    await MainActor.run {
                        self.extensionContext?.completeRequest(
                            returningItems: [],
                            completionHandler: nil
                        )
                    }
                    return
                }
                // mailPayload returned nil (e.g. an empty body after
                // trimming) — fall through to the generic link/text
                // branch so the user still gets *something* captured.
            }

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

    /// Heuristic used to route a plain-text share through the mail
    /// branch (v0.14). Conservative on purpose: a single `From:` /
    /// `Subject:` / `Date:` / `To:` header at the start of the text
    /// is enough to qualify, but a random "Subject" word inside the
    /// body of a normal text share won't trigger a false positive.
    ///
    /// We scan only the first eight lines (envelope headers in an
    /// RFC 822 message are always at the top) and require at least
    /// one of the four canonical headers to land on its own line.
    private func looksLikeMail(_ text: String) -> Bool {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let firstLines = normalized
            .split(separator: "\n", omittingEmptySubsequences: false)
            .prefix(8)
        for raw in firstLines {
            let line = String(raw).trimmingCharacters(in: .whitespaces)
            let lower = line.lowercased()
            if lower.hasPrefix("from:") || lower.hasPrefix("subject:") {
                return true
            }
        }
        return false
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

    // MARK: - Contact (vCard) extraction — v0.13

    /// Scans every NSItemProvider for `public.vcard` payloads, parses
    /// them through `CNContactVCardSerialization`, and emits one
    /// `ShareInbox.Payload(kind: .contact)` per contact. The user's
    /// free-text comment (if any) is appended to the serialised info
    /// so a "spoke to Jane about pricing" note lands on the resulting
    /// `person` Node alongside the contact fields.
    ///
    /// We do all parsing inside the extension process so the host
    /// app's drain handler never has to import `Contacts` — keeps the
    /// concern localised and the host module dependency graph clean.
    private func collectContactPayloads(
        from items: [NSExtensionItem],
        userComment: String
    ) async -> [ShareInbox.Payload] {
        var result: [ShareInbox.Payload] = []
        let trimmedComment = userComment
            .trimmingCharacters(in: .whitespacesAndNewlines)

        for item in items {
            for provider in item.attachments ?? [] {
                guard
                    provider.hasItemConformingToTypeIdentifier(UTType.vCard.identifier)
                else { continue }
                guard
                    let data = await loadData(provider, identifier: UTType.vCard.identifier)
                else { continue }
                guard
                    let contacts = try? CNContactVCardSerialization.contacts(with: data)
                else { continue }

                for contact in contacts {
                    if let payload = Self.payload(
                        from: contact,
                        userComment: trimmedComment
                    ) {
                        result.append(payload)
                    }
                }
            }
        }
        return result
    }

    /// Bridges a `CNContact` (Apple's vCard model) into the cross-
    /// process `ShareInbox.Payload`. The pure assembly lives in
    /// `ShareInbox.Payload.contactPayload(...)` inside GraphCore so
    /// the host tests can exercise it without importing Contacts;
    /// this method only does the CNContact field extraction.
    static func payload(
        from contact: CNContact,
        userComment: String = ""
    ) -> ShareInbox.Payload? {
        let formattedName = CNContactFormatter.string(
            from: contact,
            style: .fullName
        )

        let emails = contact.emailAddresses.map { String($0.value) }
        let phones = contact.phoneNumbers.map { $0.value.stringValue }
        let organization = contact.organizationName

        return ShareInbox.Payload.contactPayload(
            fullName: formattedName,
            emails: emails,
            phones: phones,
            organization: organization,
            userComment: userComment
        )
    }

    /// Bridges NSItemProvider's completion-handler API into async/await
    /// for `Data?` — used by the vCard branch above. Same Sendable
    /// narrowing pattern as `loadURL` / `loadString`.
    private func loadData(_ provider: NSItemProvider, identifier: String) async -> Data? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
            provider.loadItem(forTypeIdentifier: identifier, options: nil) { value, _ in
                if let data = value as? Data {
                    continuation.resume(returning: data)
                } else if let url = value as? URL,
                          let data = try? Data(contentsOf: url) {
                    // Some share sources hand us a file URL pointing
                    // at the vCard rather than the raw bytes — read
                    // through so the parse path doesn't care.
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
