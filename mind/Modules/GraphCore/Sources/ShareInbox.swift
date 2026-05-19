import Foundation

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

    /// One captured share — URL and/or text, plus a timestamp. We keep
    /// both fields optional so the same payload type can carry a pure
    /// text share (no URL) or a pure URL share (a Safari "share this
    /// page" with no extra commentary).
    public struct Payload: Codable, Equatable, Sendable {
        public let id: UUID
        public let url: URL?
        public let text: String?
        public let capturedAt: Date

        public init(
            id: UUID = UUID(),
            url: URL? = nil,
            text: String? = nil,
            capturedAt: Date = .now
        ) {
            self.id = id
            self.url = url
            self.text = text
            self.capturedAt = capturedAt
        }

        /// Convenience accessor: prefer the URL string for the Node
        /// title (truncated), fall back to the first non-empty line of
        /// text, fall back to a generic "Shared item" so a Node is
        /// always nameable.
        public var titleCandidate: String {
            if let url = url, let host = url.host {
                return host
            }
            if let text = text {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if let firstLine = trimmed.split(separator: "\n").first {
                    return String(firstLine.prefix(80))
                }
            }
            return "Shared item"
        }

        /// Body content for the resulting Node. URL on its own line
        /// before the comment text so the host renders it as a link in
        /// the markdown viewer.
        public var contentBody: String {
            var parts: [String] = []
            if let url = url { parts.append(url.absoluteString) }
            if let text = text, !text.isEmpty { parts.append(text) }
            return parts.joined(separator: "\n\n")
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
