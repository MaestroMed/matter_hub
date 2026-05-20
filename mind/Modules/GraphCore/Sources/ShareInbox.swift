import Foundation

/// Pure parser used by the Share Extension's mail branch (v0.14) to
/// split a raw shared email into a subject, a sender email, and a
/// body. Framework-free so the host's unit tests can exercise every
/// branch without booting the extension process or importing any
/// Mail.app-private types.
///
/// Mail.app's "Share" sheet posts the email as a single
/// `public.plain-text` item shaped like an RFC 822 envelope:
///
/// ```
/// From: Jane Doe <jane@acme.com>
/// Subject: Welcome to the beta
/// Date: Mon, 13 May 2026 14:30:00 +0200
/// To: john@example.com
///
/// Hi John, …
/// ```
///
/// The parser is line-oriented and forgiving: missing headers
/// degrade to `nil` rather than failing, and any text before the
/// first blank line that doesn't look like a header is treated as
/// part of the body so a "share selection" (no envelope at all)
/// still surfaces useful content.
public enum MailParser {
    /// Result of parsing a single raw mail share. Any field can be
    /// `nil`/empty — the consumer applies its own fallbacks.
    public struct Parsed: Equatable, Sendable {
        public let subject: String?
        public let senderEmail: String?
        public let senderDisplayName: String?
        public let body: String

        public init(
            subject: String? = nil,
            senderEmail: String? = nil,
            senderDisplayName: String? = nil,
            body: String = ""
        ) {
            self.subject = subject
            self.senderEmail = senderEmail
            self.senderDisplayName = senderDisplayName
            self.body = body
        }
    }

    /// Split `rawText` into headers + body, then extract the
    /// recognised headers (`Subject:`, `From:`). The blank-line
    /// separator is the canonical RFC 822 split; when no blank line
    /// is found we still try to identify a few leading header lines
    /// (the first N lines that match `Header: value`) so a "no
    /// trailing blank line" share doesn't lose its subject.
    public static func parse(rawText: String) -> Parsed {
        let normalized = rawText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return Parsed() }

        // Find the first blank line — that's the headers/body boundary.
        // When present, everything before is candidate headers, everything
        // after is the body. When absent, scan from the top while the
        // current line still parses as a header.
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0) }

        var headerEnd: Int? = nil
        for (i, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                headerEnd = i
                break
            }
        }

        let headerLines: [String]
        let bodyLines: [String]
        if let end = headerEnd {
            let candidateHeaders = Array(lines.prefix(end))
            // Guard against false positives: if the lines before the
            // blank don't actually contain ANY header-shaped line
            // (e.g. `Hey,\n\nbody…`), they aren't an envelope —
            // treat the whole input as body so the user never loses
            // the salutation. A single header-shaped line is enough
            // to qualify as an envelope.
            if candidateHeaders.contains(where: { isHeaderLine($0) }) {
                headerLines = candidateHeaders
                // Body starts after the blank line.
                bodyLines = Array(lines.dropFirst(end + 1))
            } else {
                headerLines = []
                bodyLines = lines
            }
        } else {
            // No blank line found — treat the leading run of
            // header-shaped lines as headers, the rest as body.
            var headerCount = 0
            for line in lines {
                if isHeaderLine(line) {
                    headerCount += 1
                } else {
                    break
                }
            }
            // If literally every line looks like a header (rare —
            // share selection of just a few headers), treat the lot
            // as headers and emit an empty body so the consumer can
            // fall back to its own assembly.
            headerLines = Array(lines.prefix(headerCount))
            bodyLines = Array(lines.dropFirst(headerCount))
        }

        // Fold RFC 822 continuation lines (a header continued on the
        // next line starts with whitespace) so `Subject: foo\n bar`
        // becomes the single field `Subject: foo bar` before we
        // dispatch on the header name.
        let foldedHeaders = foldContinuations(headerLines)

        var subject: String? = nil
        var senderEmail: String? = nil
        var senderDisplay: String? = nil
        for header in foldedHeaders {
            guard let colon = header.firstIndex(of: ":") else { continue }
            let name = header[..<colon]
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            let value = header[header.index(after: colon)...]
                .trimmingCharacters(in: .whitespaces)
            switch name {
            case "subject":
                if !value.isEmpty { subject = value }
            case "from":
                let (email, display) = splitFromHeader(value)
                if let email, !email.isEmpty { senderEmail = email }
                if let display, !display.isEmpty { senderDisplay = display }
            default:
                continue
            }
        }

        let body = bodyLines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return Parsed(
            subject: subject,
            senderEmail: senderEmail,
            senderDisplayName: senderDisplay,
            body: body
        )
    }

    // MARK: - Internals

    /// `Subject: foo` parses as a header. `Hi John,` doesn't. We
    /// guard against false-positives like `URL:` inside a body by
    /// also requiring the colon to land before any space — RFC 822
    /// header names are token strings (no whitespace) so a header
    /// always has its `:` before the first space.
    static func isHeaderLine(_ line: String) -> Bool {
        guard let colon = line.firstIndex(of: ":") else { return false }
        let name = line[..<colon]
        // Name must be non-empty and contain no whitespace — that's
        // the RFC 822 token-string definition. Continuation lines
        // (start with whitespace) aren't headers in themselves but
        // are folded into the previous header by `foldContinuations`.
        if name.isEmpty { return false }
        for char in name {
            if char.isWhitespace { return false }
        }
        // Reject obvious URLs-as-prefix (`https://...`) — the colon
        // is part of the scheme, not a header separator.
        let lower = name.lowercased()
        if lower == "http" || lower == "https" || lower == "mailto" || lower == "tel" {
            return false
        }
        return true
    }

    /// RFC 822 allows a header value to wrap onto the next line if
    /// that next line begins with whitespace. Fold those so each
    /// element of the returned array is a single complete header.
    static func foldContinuations(_ lines: [String]) -> [String] {
        var result: [String] = []
        for line in lines {
            if let first = line.first, first == " " || first == "\t", !result.isEmpty {
                // Continuation — append (with a single space) to the
                // last accumulated header.
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                result[result.count - 1] += " " + trimmed
            } else {
                result.append(line)
            }
        }
        return result
    }

    /// `Jane Doe <jane@acme.com>` → (`jane@acme.com`, `Jane Doe`).
    /// `jane@acme.com` → (`jane@acme.com`, nil).
    /// `"Jane, Doe" <jane@acme.com>` → strips the surrounding quotes.
    /// Returns nils when neither pattern matches.
    static func splitFromHeader(_ value: String) -> (email: String?, display: String?) {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return (nil, nil) }

        // Angle-bracket form: <email> at the end with optional
        // display name before it.
        if let openIdx = trimmed.lastIndex(of: "<"),
           let closeIdx = trimmed.lastIndex(of: ">"),
           openIdx < closeIdx {
            let inside = trimmed[trimmed.index(after: openIdx)..<closeIdx]
                .trimmingCharacters(in: .whitespaces)
            let email = inside.isEmpty ? nil : inside
            var display: String? = nil
            let before = trimmed[..<openIdx].trimmingCharacters(in: .whitespaces)
            if !before.isEmpty {
                // Strip surrounding quotes if present.
                if before.hasPrefix("\"") && before.hasSuffix("\"") && before.count >= 2 {
                    display = String(before.dropFirst().dropLast())
                        .trimmingCharacters(in: .whitespaces)
                } else {
                    display = before
                }
            }
            return (email, display)
        }

        // No brackets — if the whole value looks like an email,
        // treat it as the address with no display name.
        if trimmed.contains("@"), !trimmed.contains(" ") {
            return (trimmed, nil)
        }

        // Last resort: scan for the first @-bearing token, treat
        // everything else as display name. Covers `jane@acme.com
        // (Jane Doe)` and similar permissive forms.
        let tokens = trimmed.split(separator: " ").map(String.init)
        if let emailToken = tokens.first(where: { $0.contains("@") }) {
            let display = tokens
                .filter { $0 != emailToken }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            return (emailToken, display.isEmpty ? nil : display)
        }

        // Display-name-only — preserve it so the consumer can still
        // attribute the share to "Jane" even without an address.
        return (nil, trimmed)
    }
}

/// Cross-process queue used by `MINDShareExtension` to hand captured
/// payloads (URLs + text) over to the host MIND app.
///
/// Why a queue and not a direct SwiftData write?
/// ----------------------------------------------
/// The Share Extension runs in a separate process with a tiny memory
/// budget (~120MB) and a sub-second presentation deadline. Booting the
/// full SwiftData + CloudKit stack inside the extension is a recipe for
/// "share sheet hangs" reports and bouncing reviews. We instead:
///
///   1. The extension writes a `ShareInbox.Payload` to a JSON file in
///      the App Group (or `caches/` on unsigned dev loops).
///   2. The host app drains the queue on `.active` scenePhase, opens
///      SwiftData properly, creates Nodes, and clears the queue.
///
/// The queue is bounded (10 items) so an offline burst doesn't pile up.
/// Reads are atomic-ish: we read-then-truncate inside a single function
/// so concurrent shares don't get lost — the worst case is the system
/// kills the extension mid-write, which surfaces in the host as an item
/// silently missing (the user can re-share).
public enum ShareInbox {

    /// Discriminator for the shape of share the user captured. Default
    /// is `.link` (matches every payload shipped before v0.13) so older
    /// serialized queues decode cleanly without a migration.
    ///
    /// - `link`: URL + optional comment (Safari, Mail, Notes, …).
    /// - `contact`: vCard imported from Contacts.app — the resulting
    ///   Node is a `person` rather than a `capture`.
    /// - `mail`: email captured from Mail.app — the resulting Node is
    ///   a `mail` with the subject as title, body as content, and the
    ///   sender's email domain as a tag (v0.14).
    public enum Kind: String, Codable, Sendable {
        case link
        case contact
        case mail
    }

    /// One captured share — URL and/or text, plus a timestamp. We keep
    /// both fields optional so the same payload type can carry a pure
    /// text share (no URL), a pure URL share (a Safari "share this
    /// page" with no extra commentary), or a contact import (v0.13)
    /// where `title` carries the person's full name, `content` the
    /// serialized info (email/phone/company), and `attendees` the
    /// email addresses for tag extraction on the host side.
    public struct Payload: Codable, Equatable, Sendable {
        public let id: UUID
        public let url: URL?
        public let text: String?
        public let capturedAt: Date
        /// Discriminator added in v0.13. JSON-decoded with a `.link`
        /// fallback so payloads written by older extensions still
        /// surface as link captures (the host's drain handler ignores
        /// the new field and behaves as before).
        public let kind: Kind
        /// Human-readable title for the resulting Node. v0.13 — the
        /// vCard parser feeds the formatted full name here; the link
        /// branch leaves it `nil` and `titleCandidate` falls back to
        /// the URL host as before.
        public let title: String?
        /// Pre-rendered body for the resulting Node. v0.13 — vCard
        /// imports serialise email + phone + company line-by-line so
        /// the host doesn't need to know about CNContact. Link
        /// imports leave it `nil` and `contentBody` rebuilds it from
        /// `url` + `text` like before.
        public let content: String?
        /// Email addresses extracted from a vCard, in source order
        /// (first email is the primary). The host uses the first
        /// address's domain as a searchable tag on the `person` Node.
        /// Always `nil` for link payloads.
        public let attendees: [String]?

        public init(
            id: UUID = UUID(),
            url: URL? = nil,
            text: String? = nil,
            capturedAt: Date = .now,
            kind: Kind = .link,
            title: String? = nil,
            content: String? = nil,
            attendees: [String]? = nil
        ) {
            self.id = id
            self.url = url
            self.text = text
            self.capturedAt = capturedAt
            self.kind = kind
            self.title = title
            self.content = content
            self.attendees = attendees
        }

        // MARK: - Backward-compatible JSON

        /// JSON decoding tolerates payloads serialised by the v0.3 →
        /// v0.12 extension (no `kind`, no `title`/`content`/`attendees`
        /// keys). Missing fields default to a `.link` payload — the
        /// host's drain handler treats those exactly as before so an
        /// extension update / app update mismatch never drops shares.
        enum CodingKeys: String, CodingKey {
            case id, url, text, capturedAt, kind, title, content, attendees
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try container.decode(UUID.self, forKey: .id)
            self.url = try container.decodeIfPresent(URL.self, forKey: .url)
            self.text = try container.decodeIfPresent(String.self, forKey: .text)
            self.capturedAt = try container.decode(Date.self, forKey: .capturedAt)
            // v0.14 — tolerant raw-string decode so an extension that
            // ships a future `kind` value the host doesn't know yet
            // (e.g. a Mail extension talking to an older v0.12 host)
            // degrades gracefully to `.link` instead of failing the
            // whole drain pass. Older queues without the `kind` key
            // continue to land here as `.link` too.
            if let raw = try container.decodeIfPresent(String.self, forKey: .kind),
               let parsed = Kind(rawValue: raw) {
                self.kind = parsed
            } else {
                self.kind = .link
            }
            self.title = try container.decodeIfPresent(String.self, forKey: .title)
            self.content = try container.decodeIfPresent(String.self, forKey: .content)
            self.attendees = try container.decodeIfPresent([String].self, forKey: .attendees)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encodeIfPresent(url, forKey: .url)
            try container.encodeIfPresent(text, forKey: .text)
            try container.encode(capturedAt, forKey: .capturedAt)
            try container.encode(kind, forKey: .kind)
            try container.encodeIfPresent(title, forKey: .title)
            try container.encodeIfPresent(content, forKey: .content)
            try container.encodeIfPresent(attendees, forKey: .attendees)
        }

        /// Convenience accessor: contact payloads use their explicit
        /// `title` (the formatted full name); link payloads prefer the
        /// URL host, fall back to the first non-empty line of text,
        /// fall back to a generic "Shared item" so a Node is always
        /// nameable. v0.13 — when a contact has no name (just an
        /// email), we fall through to `text`/email so the user still
        /// sees something useful.
        public var titleCandidate: String {
            if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return title
            }
            if let url = url, let host = url.host {
                return host
            }
            if let text = text {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if let firstLine = trimmed.split(separator: "\n").first {
                    return String(firstLine.prefix(80))
                }
            }
            if let attendees, let firstEmail = attendees.first {
                return firstEmail
            }
            return "Shared item"
        }

        /// Body content for the resulting Node. Contact payloads use
        /// their pre-rendered `content`. Link payloads stitch URL +
        /// text together, URL on its own line first so the host
        /// renders it as a link in the markdown viewer.
        public var contentBody: String {
            if let content, !content.isEmpty {
                return content
            }
            var parts: [String] = []
            if let url = url { parts.append(url.absoluteString) }
            if let text = text, !text.isEmpty { parts.append(text) }
            return parts.joined(separator: "\n\n")
        }

        /// Extracts the host portion of the first attendee email so
        /// the host app can tag the resulting `person` Node with the
        /// company domain (`acme.com` from `john@acme.com`). Returns
        /// `nil` for link payloads, empty attendees, or malformed
        /// addresses without a `@`.
        public var primaryEmailDomain: String? {
            guard let attendees, let first = attendees.first else { return nil }
            return Self.emailDomain(from: first)
        }

        /// Pure helper used by `primaryEmailDomain` and by tests.
        /// `john@acme.com` → `acme.com`, `weird-no-at` → `nil`,
        /// `multi@chunk@a.com` → `a.com` (last `@` wins, since the
        /// local-part is allowed to contain literal `@` in quotes).
        public static func emailDomain(from email: String) -> String? {
            let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let atIndex = trimmed.lastIndex(of: "@") else { return nil }
            let domain = String(trimmed[trimmed.index(after: atIndex)...])
                .lowercased()
                .trimmingCharacters(in: .whitespaces)
            return domain.isEmpty ? nil : domain
        }

        /// Pure factory used by the Share Extension's Mail branch
        /// (v0.14). Kept here, framework-free, so the host's unit
        /// tests can exercise subject/sender/body extraction without
        /// importing any iOS-only headers. The Share Extension feeds
        /// in the raw text it lifted off the `public.plain-text`
        /// item provider (Mail.app's "Share" exposes the email as
        /// plain text shaped like an RFC 822 message — `From:` /
        /// `Subject:` / `Date:` headers, a blank line, then the body).
        ///
        /// Title fallback chain: explicit `Subject:` header → first
        /// non-empty body line → "(Sans sujet)" via the host's
        /// localized fallback (the helper returns `nil` for the
        /// `title` field in the no-subject case and lets the
        /// `titleCandidate` accessor + host drainer pick the right
        /// localised string).
        ///
        /// Content is the body of the email, with the leading
        /// headers and signature trimmed. The user's free-text
        /// comment (typed in the share sheet) is prepended on its
        /// own paragraph so a "FYI" note lands above the quoted
        /// email when rendered in MarkdownView.
        ///
        /// Returns `nil` when the input is empty after trimming —
        /// nothing to capture means no Node.
        public static func mailPayload(
            rawText: String,
            userComment: String = "",
            capturedAt: Date = .now
        ) -> Payload? {
            let trimmedRaw = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedRaw.isEmpty else { return nil }

            let parsed = MailParser.parse(rawText: trimmedRaw)
            let trimmedComment = userComment
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // Body assembly: user comment on top (when present), then
            // a blank line, then the parsed body. When the parser
            // couldn't separate headers from body (no blank line) we
            // fall through to the entire raw text so the user never
            // loses content to a parse miss.
            var bodyParts: [String] = []
            if !trimmedComment.isEmpty { bodyParts.append(trimmedComment) }
            let parsedBody = parsed.body.trimmingCharacters(in: .whitespacesAndNewlines)
            if !parsedBody.isEmpty {
                bodyParts.append(parsedBody)
            } else if parsed.subject == nil && parsed.senderEmail == nil {
                // No headers detected at all — keep the raw text
                // intact rather than emit an empty Node body.
                bodyParts.append(trimmedRaw)
            }
            let content = bodyParts.joined(separator: "\n\n")

            // Attendees carries the sender email (when present) so
            // the host can tag the resulting Node with the company
            // domain — same convention as the contact branch.
            let attendees: [String]? = parsed.senderEmail.map { [$0] }

            return Payload(
                url: nil,
                text: nil,
                capturedAt: capturedAt,
                kind: .mail,
                title: parsed.subject,
                content: content.isEmpty ? nil : content,
                attendees: attendees
            )
        }

        /// Pure factory used by the Share Extension's vCard branch
        /// (v0.13). Kept here, framework-free, so the host's unit
        /// tests can exercise the title/content/attendees assembly
        /// without depending on CNContact. The extension extracts the
        /// raw strings from `CNContactVCardSerialization` and feeds
        /// them in.
        ///
        /// Title fallback chain: formatted full name → first email →
        /// company name → nothing (returns nil — a vCard with no
        /// identifying info isn't worth surfacing as a Node).
        ///
        /// Content is serialised line-by-line so the host's
        /// Markdown renderer prints it cleanly: primary email, extra
        /// emails, phones, company, user comment.
        public static func contactPayload(
            fullName: String?,
            emails: [String],
            phones: [String],
            organization: String,
            userComment: String = "",
            capturedAt: Date = .now
        ) -> Payload? {
            let trimmedName = fullName?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanEmails = emails
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let cleanPhones = phones
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let trimmedOrg = organization
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedComment = userComment
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let resolvedTitle: String? = {
                if let n = trimmedName, !n.isEmpty { return n }
                if let e = cleanEmails.first { return e }
                if !trimmedOrg.isEmpty { return trimmedOrg }
                return nil
            }()
            guard let title = resolvedTitle else { return nil }

            var lines: [String] = []
            for email in cleanEmails { lines.append(email) }
            for phone in cleanPhones { lines.append(phone) }
            if !trimmedOrg.isEmpty { lines.append(trimmedOrg) }
            if !trimmedComment.isEmpty { lines.append(trimmedComment) }
            let content = lines.joined(separator: "\n")

            return Payload(
                url: nil,
                text: nil,
                capturedAt: capturedAt,
                kind: .contact,
                title: title,
                content: content.isEmpty ? nil : content,
                attendees: cleanEmails.isEmpty ? nil : cleanEmails
            )
        }
    }

    /// Maximum number of pending payloads kept on disk. Beyond this
    /// the oldest entries are dropped. Sized to be plenty for a normal
    /// burst (3–5 shares in a row from Safari tabs) without letting a
    /// runaway loop fill the App Group.
    public static let maxPendingPayloads = 10

    /// Filename inside the App Group container (or caches fallback)
    /// holding the JSON-encoded `[Payload]` queue.
    public static let queueFilename = "ShareInbox.json"

    // MARK: - Public API

    /// Append a payload to the on-disk queue. Safe to call from the
    /// Share Extension process — the file is rewritten in one shot so
    /// a crash mid-call loses at most the in-flight item (not the
    /// whole queue).
    @discardableResult
    public static func enqueue(
        _ payload: Payload,
        at url: URL? = nil
    ) -> Bool {
        guard let fileURL = url ?? queueFileURL() else { return false }
        var existing = readQueue(at: fileURL)
        existing.append(payload)
        if existing.count > maxPendingPayloads {
            existing = Array(existing.suffix(maxPendingPayloads))
        }
        return writeQueue(existing, to: fileURL)
    }

    /// Read every pending payload and atomically clear the queue.
    /// Returns the payloads in insertion order (oldest first), so the
    /// host can create Nodes in the order the user actually shared.
    @discardableResult
    public static func drain(at url: URL? = nil) -> [Payload] {
        guard let fileURL = url ?? queueFileURL() else { return [] }
        let pending = readQueue(at: fileURL)
        if !pending.isEmpty {
            _ = writeQueue([], to: fileURL)
        }
        return pending
    }

    /// Peek without draining — useful for tests and for a future
    /// "pending shares" debug screen.
    public static func peek(at url: URL? = nil) -> [Payload] {
        guard let fileURL = url ?? queueFileURL() else { return [] }
        return readQueue(at: fileURL)
    }

    /// Empties the queue without surfacing the contents. Used by the
    /// Settings → "Wipe all data" path and by tests.
    @discardableResult
    public static func clear(at url: URL? = nil) -> Bool {
        guard let fileURL = url ?? queueFileURL() else { return false }
        return writeQueue([], to: fileURL)
    }

    // MARK: - Known-host → client name extraction

    /// Maps the host of a URL to a canonical client / brand name when
    /// it's a well-known SaaS the user is likely tracking. Returning
    /// non-nil tells the host app to create a `client` Node alongside
    /// the capture Node so the captured URL is filed under the right
    /// bucket from day one.
    ///
    /// Keep the list small and high-signal — false positives are worse
    /// than misses. Add hosts as Mehdi requests them.
    public static func knownClientName(for url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        // Strip an optional leading `www.` so `www.stripe.com` and
        // `stripe.com` both hit the same row.
        let normalized = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host

        for (suffix, brand) in knownHostSuffixes {
            if normalized == suffix || normalized.hasSuffix("." + suffix) {
                return brand
            }
        }
        return nil
    }

    /// Source-of-truth list of (host suffix, canonical brand name)
    /// pairs. Suffix match means `dashboard.stripe.com` resolves the
    /// same brand as `stripe.com`. Order doesn't matter — the lookup
    /// is exhaustive.
    static let knownHostSuffixes: [(String, String)] = [
        ("stripe.com", "Stripe"),
        ("notion.so", "Notion"),
        ("notion.site", "Notion"),
        ("linear.app", "Linear"),
        ("github.com", "GitHub"),
        ("figma.com", "Figma"),
        ("vercel.com", "Vercel"),
        ("netlify.com", "Netlify"),
        ("shopify.com", "Shopify"),
        ("slack.com", "Slack"),
        ("airtable.com", "Airtable"),
        ("anthropic.com", "Anthropic"),
        ("openai.com", "OpenAI"),
        ("apple.com", "Apple"),
        ("google.com", "Google"),
        ("cloudflare.com", "Cloudflare"),
    ]

    // MARK: - Storage location

    /// Resolves the App Group container URL when entitled, falling
    /// back to the caller-process caches directory when not. Returning
    /// `nil` means we literally cannot find a writable place — that's
    /// catastrophic and the caller should surface it.
    public static func queueFileURL() -> URL? {
        if let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: GraphCore.appGroupIdentifier
        ) {
            return groupURL.appendingPathComponent(queueFilename)
        }
        // Unsigned dev loop: there is no App Group container, so the
        // host and extension can't share a file. The host can still
        // exercise the queue against its own caches directory so the
        // unit tests work end-to-end.
        let fm = FileManager.default
        if let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
            return caches.appendingPathComponent(queueFilename)
        }
        return nil
    }

    // MARK: - Internals

    private static func readQueue(at url: URL) -> [Payload] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Payload].self, from: data)) ?? []
    }

    @discardableResult
    private static func writeQueue(_ payloads: [Payload], to url: URL) -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            // Ensure the parent directory exists — first run after
            // install can race the directory creation otherwise.
            let directory = url.deletingLastPathComponent()
            try? FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(payloads)
            try data.write(to: url, options: [.atomic])
            return true
        } catch {
            return false
        }
    }
}
