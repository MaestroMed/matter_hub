import Foundation
import GraphCore

/// v0.28 — Pure-function core of the Discovery Call Prep Dossier.
///
/// Everything here is deterministic + side-effect-free so the test
/// suite can lock the contract without touching EventKit, the
/// network, or SwiftData. The host App layer combines the heuristics
/// below with audit data (looked up by attached `audit`-kind Nodes)
/// and AI enrichment (via `MeetingBriefEnricher`, which soft-fails
/// to these heuristics).
///
/// Public API:
///
///   - `detectClient(in:from:)` — match an event to a client Node
///     by attendee-email domain.
///   - `draftDiscoveryQuestions(for:event:)` — return exactly 5 FR
///     discovery questions tailored to the client when possible,
///     generic when not.
///   - `draftElevatorOpening(for:event:)` — return a 30-second
///     opening line in Mehdi's voice, name-checking the first
///     attendee and the client when both are known.
///   - `assemble(for:clients:audits:asOf:)` — convenience aggregator
///     that runs the three above + assembles a `MeetingBrief` with
///     empty news/intel sections so the host App can render
///     immediately and let the async enricher backfill later.
public enum MeetingBriefBuilder {

    // MARK: - Client detection

    /// Walks the event's attendee emails, extracts the domain part
    /// (`john@stripe.com` → `stripe.com`), and returns the first
    /// matching client Node whose `content` (or `sourceURL`) holds
    /// a URL on the same root domain — `stripe.com` matches
    /// `https://stripe.com`, `https://www.stripe.com`, and
    /// `https://dashboard.stripe.com`.
    ///
    /// Returns `nil` when:
    /// - the event has no attendee emails (most personal events),
    /// - no client Node holds a URL on any of those domains,
    /// - the `nodes` array contains zero `.client`-kind Nodes.
    ///
    /// Deterministic: when multiple clients match, the first match
    /// in `nodes`' iteration order wins. Callers that care about
    /// recency / score should pre-sort.
    public static func detectClient(
        in event: CalendarEvent,
        from nodes: [Node]
    ) -> Node? {
        guard !event.attendeeEmails.isEmpty, !nodes.isEmpty else { return nil }

        // Reduce every attendee email to its apex domain via the
        // same `rootHost` collapse the client URLs go through. This
        // makes `jane.doe@dashboard.stripe.com` match a client whose
        // URL is `https://stripe.com` and vice versa.
        let domains = Set(event.attendeeEmails.compactMap { email -> String? in
            guard let domain = extractDomain(fromEmail: email) else { return nil }
            return rootHost(of: domain)
        })
        guard !domains.isEmpty else { return nil }

        let clients = nodes.filter { $0.kindRaw == NodeKind.client.rawValue }
        for client in clients {
            let candidateURLs: [String] = [
                client.sourceURL,
                client.content,
            ].compactMap { $0 }
            for raw in candidateURLs {
                guard let host = rootHost(of: raw) else { continue }
                if domains.contains(host) {
                    return client
                }
            }
        }
        return nil
    }

    // MARK: - Discovery questions

    /// Returns exactly 5 calibrated discovery questions, in French.
    /// When `client` is non-nil and the client's `tags` carry well-
    /// known audit-finding signals (`security:low`, `traffic:high`,
    /// `seo:weak`, `conversion:weak`), the question set is biased
    /// toward the matching domain. Generic 5-question fallback
    /// otherwise.
    public static func draftDiscoveryQuestions(
        for client: Node?,
        event: CalendarEvent
    ) -> [String] {
        // Anchor: every set MUST end at exactly 5 questions so the
        // sheet's "Questions discovery (5)" header is always honest.
        var questions: [String] = []

        let tags = Set((client?.tags ?? []).map { $0.lowercased() })

        // Domain-specific questions injected first when relevant.
        if tags.contains("security:low") {
            questions.append("Comment gérez-vous aujourd'hui les certificats SSL et les en-têtes de sécurité ?")
        }
        if tags.contains("traffic:high") {
            questions.append("Quel est votre principal goulot de scaling à mesure que le trafic monte ?")
        }
        if tags.contains("seo:weak") {
            questions.append("Sur quels mots-clés stratégiques préférez-vous ne plus apparaître en page 3 de Google ?")
        }
        if tags.contains("conversion:weak") {
            questions.append("Quelle étape du tunnel de conversion vous coûte le plus de clients aujourd'hui ?")
        }

        // Generic qualifying core, in priority order. Items get
        // appended until the set hits 5 — duplicates from the
        // domain-specific layer above are skipped via `firstIndex`.
        let generic: [String] = [
            "Qu'est-ce qui vous a motivé à prendre cette discussion aujourd'hui ?",
            "Quels sont les trois résultats que vous voulez absolument obtenir d'ici la fin du trimestre ?",
            "Comment mesurez-vous actuellement le succès sur ce sujet ?",
            "Si nous résolvons ce problème ensemble, qu'est-ce que ça change concrètement pour votre équipe ?",
            "Qui d'autre est impliqué dans la décision et quel est leur point de vue ?",
        ]
        for q in generic where questions.count < 5 && !questions.contains(q) {
            questions.append(q)
        }

        // Hard cap — domain-specific layer can add at most 4, generic
        // fills the rest, so we should never exceed 5; clip defensively.
        if questions.count > 5 {
            questions = Array(questions.prefix(5))
        }
        return questions
    }

    // MARK: - Elevator opening

    /// Returns a 30-second opening line, in French, in Mehdi's voice.
    /// Template: "Bonjour {firstAttendeeFirstName}, content de vous
    /// parler aujourd'hui. J'ai jeté un œil à {clientName}, et j'ai
    /// noté 3 axes prometteurs." Falls back gracefully when either
    /// the attendee or the client is unknown.
    public static func draftElevatorOpening(
        for client: Node?,
        event: CalendarEvent
    ) -> String {
        let firstName = firstAttendeeFirstName(in: event)
        let clientName = client?.title.trimmingCharacters(in: .whitespacesAndNewlines)

        switch (firstName, clientName?.isEmpty == false ? clientName : nil) {
        case let (name?, brand?):
            return "Bonjour \(name), content de vous parler aujourd'hui. J'ai jeté un œil à \(brand), et j'ai noté 3 axes prometteurs."
        case let (name?, nil):
            return "Bonjour \(name), content de vous parler aujourd'hui. J'ai pris le temps de préparer ce point pour qu'on aille droit au sujet."
        case let (nil, brand?):
            return "Bonjour à toute l'équipe, content de vous parler aujourd'hui. J'ai jeté un œil à \(brand), et j'ai noté 3 axes prometteurs."
        case (nil, nil):
            return "Bonjour, content de vous parler aujourd'hui. J'ai pris quelques minutes pour préparer ce point afin qu'on aille droit au sujet."
        }
    }

    // MARK: - Aggregator

    /// Convenience aggregator the host App uses to mint a brief from
    /// raw graph state. Touches `Node` (a SwiftData `@Model` type)
    /// which lives on the MainActor — hence the isolation. The
    /// resulting `MeetingBrief` is fully Sendable: the matched
    /// client is captured into a `DetectedClient` snapshot before
    /// the function returns. Recent news + attendee LinkedIn intel
    /// default to empty (the async `MeetingBriefEnricher` fills
    /// them in later); audit highlights are derived from the
    /// matched client's tags via `auditHighlights(for:)`.
    @MainActor
    public static func assemble(
        for event: CalendarEvent,
        clients: [Node],
        asOf now: Date = .now
    ) -> MeetingBrief {
        let client = detectClient(in: event, from: clients)
        let snapshot = client.map(DetectedClient.init(node:))
        return MeetingBrief(
            event: event,
            detectedClient: snapshot,
            recentNews: [],
            auditHighlights: auditHighlights(for: client),
            attendeeIntel: attendeeIntel(for: event),
            discoveryQuestions: draftDiscoveryQuestions(for: client, event: event),
            elevatorOpening: draftElevatorOpening(for: client, event: event),
            generatedAt: now
        )
    }

    // MARK: - Heuristic helpers (public so tests can pin them too)

    /// Distils a client's tag set into the 0-3 most-load-bearing
    /// audit highlights for the sheet. Tag taxonomy is the same
    /// `<domain>:<severity>` format the LeadScorer (v0.27) and the
    /// AuditController already mint, so MIND has a single source of
    /// truth across the app.
    public static func auditHighlights(for client: Node?) -> [BriefBullet] {
        guard let client else { return [] }
        let tags = Set(client.tags.map { $0.lowercased() })

        var bullets: [BriefBullet] = []
        if tags.contains("security:low") {
            bullets.append(BriefBullet(
                text: "Score sécurité bas : HSTS et CSP manquants — risque d'audit MITM.",
                source: "internal:audit"
            ))
        }
        if tags.contains("seo:weak") {
            bullets.append(BriefBullet(
                text: "SEO fragile : 0 balise schema.org détectée sur la landing principale.",
                source: "internal:audit"
            ))
        }
        if tags.contains("conversion:weak") {
            bullets.append(BriefBullet(
                text: "Tunnel : CTA principal sous la ligne de flottaison, friction de 4 clics avant le panier.",
                source: "internal:audit"
            ))
        }
        if tags.contains("traffic:high") {
            bullets.append(BriefBullet(
                text: "Trafic estimé > 100k visites/mois : levier ROI immédiat sur les Quick Wins.",
                source: "internal:audit"
            ))
        }
        // Truncate to 3 — the sheet section guarantees room for 3
        // tiles, more would push the questions below the fold.
        return Array(bullets.prefix(3))
    }

    /// Builds `AttendeeIntel` value objects from the raw event
    /// attendees. Role / LinkedIn URL are nil here — the async
    /// enricher fills them in by reading the `person`-kind Nodes
    /// in the graph (vCard captures from v0.13) when present.
    public static func attendeeIntel(for event: CalendarEvent) -> [AttendeeIntel] {
        let emails = event.attendeeEmails
        let names = event.attendees
        var out: [AttendeeIntel] = []
        let count = max(emails.count, names.count)
        for index in 0..<count {
            let email = index < emails.count ? emails[index] : ""
            let displayName: String = {
                if index < names.count, !names[index].isEmpty { return names[index] }
                if let email = email.split(separator: "@").first {
                    return String(email).replacingOccurrences(of: ".", with: " ")
                }
                return ""
            }()
            guard !email.isEmpty || !displayName.isEmpty else { continue }
            out.append(AttendeeIntel(
                email: email,
                displayName: displayName,
                role: nil,
                linkedInURL: nil,
                notes: nil
            ))
        }
        return out
    }

    // MARK: - Naming helpers (private)

    /// `john.doe@stripe.com` → `john`. Falls back to the bare local
    /// part when there's no `.` (e.g. `mehdi@…`).
    static func firstAttendeeFirstName(in event: CalendarEvent) -> String? {
        // Prefer the structured display name from EventKit. iCloud
        // returns "Jane Doe" reliably for invited contacts.
        if let raw = event.attendees.first {
            let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if let first = normalized.split(separator: " ").first {
                let cleaned = String(first).trimmingCharacters(in: .punctuationCharacters)
                if !cleaned.isEmpty { return cleaned.capitalized(with: .current) }
            }
        }
        // Fallback: derive a first name from the local part of the
        // first email — `john.doe@…` → `John`, `mehdi@…` → `Mehdi`.
        if let email = event.attendeeEmails.first,
           let local = email.split(separator: "@").first {
            let firstChunk = String(local).split(separator: ".").first.map(String.init) ?? String(local)
            let cleaned = firstChunk.trimmingCharacters(in: .punctuationCharacters)
            if !cleaned.isEmpty { return cleaned.capitalized(with: .current) }
        }
        return nil
    }

    /// `john@stripe.com` → `stripe.com`. Returns nil when there's no
    /// `@` or no domain part. Lowercased for stable matching.
    static func extractDomain(fromEmail email: String) -> String? {
        let parts = email.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else { return nil }
        let domain = parts[1].lowercased()
        return domain.isEmpty ? nil : String(domain)
    }

    /// `www.stripe.com` → `stripe.com`. Idempotent — already-bare
    /// hosts pass through unchanged.
    static func rootDomain(from domain: String) -> String? {
        let lowered = domain.lowercased()
        if lowered.hasPrefix("www.") {
            return String(lowered.dropFirst(4))
        }
        return lowered
    }

    /// Parses any URL-shaped string (with or without scheme) and
    /// returns its bare root host — `https://dashboard.stripe.com/x`
    /// → `stripe.com`, `stripe.com` → `stripe.com`. The two-segment
    /// fallback (`acme.com`) handles the very common case where a
    /// client Node stores `acme.com` in `content` without a scheme.
    static func rootHost(of raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }

        // Try parsing as a URL first to grab the host. Some Node
        // payloads carry a bare domain ("stripe.com") which URL()
        // happily parses with a nil host, so we fall through to the
        // raw-string path when that happens.
        var host: String?
        if let url = URL(string: trimmed), let h = url.host {
            host = h
        } else if let url = URL(string: "https://\(trimmed)"), let h = url.host {
            host = h
        }
        let candidate = host ?? trimmed
        let withoutPath = candidate.split(separator: "/").first.map(String.init) ?? candidate
        let bare: String = {
            if withoutPath.hasPrefix("www.") { return String(withoutPath.dropFirst(4)) }
            return withoutPath
        }()
        // Strip an http(s) prefix if it leaked through (defensive).
        let cleaned = bare
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")

        // Reduce subdomains to the apex by keeping the last 2 labels.
        // `dashboard.stripe.com` → `stripe.com`, `stripe.com` →
        // `stripe.com`. This is a deliberate two-label simplification
        // — country TLDs like `acme.co.uk` collapse to `co.uk`, which
        // would falsely match anything on `.co.uk`. We don't ship
        // .co.uk clients today; revisit if that changes.
        let labels = cleaned.split(separator: ".")
        guard labels.count >= 2 else { return cleaned.isEmpty ? nil : cleaned }
        return labels.suffix(2).joined(separator: ".")
    }
}
