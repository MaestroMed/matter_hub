import Foundation
import GraphCore

/// v1.0-alpha.13 — Pure prompt assembly + response parsing for the
/// AI Reply Composer that lives inside `LeadDetailSheet`.
///
/// The composer turns a single inbound lead into **3 distinct reply
/// variants** — one per `OutreachReply.Angle` (direct /
/// consultative / similarCase). Each angle has its own instruction
/// block so Claude doesn't smear the personalities. The builder
/// stays pure so the test suite locks every angle's prompt anchor
/// without round-tripping the cloud LLM.
///
/// Why a separate builder from `OutreachPromptBuilder`
/// ---------------------------------------------------
/// Sales outreach is **cold** — the prospect has never heard of
/// Mehdi. The reply composer is **warm** — the lead just filled a
/// contact form and is waiting for a response. The instructions
/// differ enough that sharing the v0.26 builder would smear both
/// surfaces. They share the JSON envelope (variants array) and the
/// `SenderProfile` value type so the parser stays consistent.
public enum LeadReplyPromptBuilder {
    /// Word-per-minute rate used to estimate per-variant read time
    /// on the chosen reply. 220 WPM matches `OutreachPromptBuilder`
    /// so the two surfaces stay in lock-step.
    public static let readingWordsPerMinute: Double = 220

    // MARK: - Prompt

    /// Build the full prompt Claude receives. Deterministic for
    /// identical inputs so the future "régénérer" CTA on the
    /// composer can hit a cache.
    public static func build(
        lead: Lead,
        project: Project?,
        similarProjects: [Project] = [],
        sender: SenderProfile = .default
    ) -> String {
        // Sender / tone — mirrors OutreachPromptBuilder's branching
        // so Mehdi's voice stays consistent between cold + warm
        // surfaces.
        let toneInstruction: String
        switch sender.voice {
        case .friendly:
            toneInstruction = "warm, conversational French agency tone — use 'vous' on a first reply (you don't know if the lead is comfortable with 'tu' yet), short sentences, no corporate boilerplate, a touch of humanity ok."
        case .direct:
            toneInstruction = "direct, no fluff, leads with a concrete next step or a sharp answer to the lead's question — short paragraphs, no 'merci pour votre message', open with the substance."
        case .formal:
            toneInstruction = "formal French business register — use 'vous', full salutation, no contractions, polite but firm."
        }

        // Lead block — surfaces everything Claude needs to ground
        // the reply: contact identity, message verbatim, project
        // host. Optional fields degrade gracefully.
        let contactLine = leadContactLine(lead: lead)
        let projectLine: String
        if let project {
            projectLine = "- Project context: \(escape(project.name)) on \(escape(project.host))"
        } else {
            projectLine = "- Project context: unknown — keep the reply project-agnostic, never invent a project name"
        }
        let messageBody = lead.message.trimmingCharacters(in: .whitespacesAndNewlines)
        let messageBlock: String
        if messageBody.isEmpty {
            messageBlock = """
            Lead message body: EMPTY — the visitor submitted the form without writing anything. Open with a one-line acknowledgement + a request for what they're looking for, before proposing next steps.
            """
        } else {
            messageBlock = """
            Lead message body (quoted verbatim, do NOT alter when quoting back):
            \"\"\"
            \(escape(messageBody))
            \"\"\"
            """
        }

        // SimilarCase grounding — when similarProjects is empty the
        // angle is told to fall back to a generic past-engagement
        // sentence so the JSON parser still gets a valid third
        // variant.
        let similarCaseBlock: String
        if !similarProjects.isEmpty {
            let bullets = similarProjects.prefix(3).map { project in
                "    - \(escape(project.name)) (\(escape(project.host)))"
            }.joined(separator: "\n")
            similarCaseBlock = """
            Similar past engagements you can name in the "similarCase" variant:
            \(bullets)
            """
        } else {
            similarCaseBlock = """
            Similar past engagements: NONE provided. For the "similarCase" variant, reference a generic "un client de taille similaire dans le même secteur" without inventing a fake company name.
            """
        }

        return """
        You are the reply assistant for \(sender.name), a \(sender.title) running the Numelite agency. Generate 3 distinct reply drafts (in French, \(sender.voice.rawValue) voice) to the inbound lead below. Each variant must take a different angle — never repeat an angle across the 3 variants. The lead just filled a contact form on \(sender.name)'s deployed site, so this is a WARM reply — they're already expecting a response.

        Lead:
        \(contactLine)
        - Form type: \(lead.formTypeEnum.rawValue)
        - Received: \(lead.receivedAt.ISO8601Format())
        \(projectLine)

        \(messageBlock)

        \(similarCaseBlock)

        Sender voice: \(toneInstruction)
        Sign every reply with: \(sender.signature)

        Angles (exactly one variant per angle, no repeats):
          - "direct"        → answers the lead's question concisely AND proposes a concrete call slot. Maximum 3 short paragraphs. Open with the substance, never with "merci pour votre message". If the lead asked about price, give a price range; if they asked about timeline, give a timeline range; if their message is empty, propose a 15-min discovery call.
          - "consultative"  → asks exactly 2 qualifying questions before talking pricing or timeline. The 2 questions must be specific to the lead's message (e.g. "Quel est le périmètre de la refonte: pages vitrines, e-commerce, application web?" / "Avez-vous un délai de mise en ligne en tête?"). Closes with a soft "Une fois ces deux points clarifiés, je vous propose un créneau pour échanger." Never lists more than 2 questions — anything more and the lead disengages.
          - "similarCase"   → opens with a 1-2 sentence reference to a similar past engagement (use the past engagement(s) listed above; fall back to a generic peer when none provided), then mirrors the lead's ask back as a proposal. Closes with a single call to action.

        Output rules:
          - 3-5 short paragraphs per reply, max 180 words total per reply, plain text only (no markdown, no HTML), single blank line between paragraphs.
          - Each reply must address the lead by their first name when known (\"\(escape(firstName(of: lead)))\") — when unknown, open with "Bonjour,".
          - Each reply must reference the lead's project context (\(escape(project?.name ?? lead.contactName))) at least once where natural.
          - Each reply must end with exactly ONE call to action sentence — never multiple CTAs back-to-back.
          - Sign every reply on its own line with: \(sender.signature)
          - Never fabricate metrics, never invent press quotes, never promise a feature \(sender.name) hasn't shipped.

        Reply STRICTLY with valid JSON, no backticks, no prose before or after, no markdown. Exact schema:

        {
          "variants": [
            {
              "angle": "direct" | "consultative" | "similarCase",
              "body": "<3-5 short paragraphs, plain text, ≤ 180 words>"
            }
          ]
        }

        Rules:
          - Exactly 3 variants, each with a distinct angle (one direct, one consultative, one similarCase).
          - No additional fields outside the schema. No text outside the JSON object.
        """
    }

    // MARK: - Response parsing

    /// Strip fenced-code wrappers Claude occasionally adds even when
    /// asked for raw JSON. Mirrors `OutreachPromptBuilder.stripFences`.
    public static func stripFences(_ response: String) -> String {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }
        return trimmed
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// JSON shape the parser decodes. Public so tests can build
    /// their own response strings without depending on private
    /// scopes.
    public struct Payload: Codable, Equatable, Sendable {
        public let variants: [Variant]

        public struct Variant: Codable, Equatable, Sendable {
            public let angle: String
            public let body: String

            public init(angle: String, body: String) {
                self.angle = angle
                self.body = body
            }
        }

        public init(variants: [Variant]) {
            self.variants = variants
        }
    }

    /// Decode the LLM response into a fresh `[OutreachReply]`. Soft-
    /// fails to `[]` only when the response can't be decoded at all
    /// — partial decodes (e.g. 2 of 3 variants well-formed) keep
    /// the well-formed entries so the user sees something rather
    /// than nothing. Unknown angle strings fall back to `.direct`
    /// rather than dropping the variant entirely.
    public static func parse(response: String) -> [OutreachReply] {
        let raw = stripFences(response)
        guard let data = raw.data(using: .utf8) else { return [] }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return []
        }
        return payload.variants.map { variant in
            let angle = OutreachReply.Angle(rawValue: variant.angle) ?? .direct
            return OutreachReply(angle: angle, body: variant.body)
        }
    }

    // MARK: - Helpers

    private static func leadContactLine(lead: Lead) -> String {
        let name = lead.contactName.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = lead.contactEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            return "- Lead: \(escape(name))" + (email.isEmpty ? "" : " <\(escape(email))>")
        }
        if !email.isEmpty {
            return "- Lead: \(escape(email)) (email only, no name provided)"
        }
        return "- Lead: anonymous form submission (no contact info captured)"
    }

    private static func firstName(of lead: Lead) -> String {
        let trimmed = lead.contactName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return String(trimmed.split(separator: " ").first ?? "")
    }

    private static func escape(_ source: String) -> String {
        source
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }
}

// MARK: - OutreachReply value

/// One reply variant produced by `OutreachEmailGenerator.leadReply`.
/// Mirrors `OutreachEmail` in shape but doesn't carry a subject —
/// the composer is always replying to an existing thread, the
/// subject line is set by Mail.app's threading.
public struct OutreachReply: Sendable, Identifiable, Equatable, Hashable {
    public let id: UUID
    public let angle: Angle
    public let body: String
    public let estimatedReadTimeSeconds: Int

    public init(
        id: UUID = UUID(),
        angle: Angle,
        body: String
    ) {
        self.id = id
        self.angle = angle
        self.body = body
        let words = body.split(whereSeparator: { $0.isWhitespace }).count
        self.estimatedReadTimeSeconds = max(
            10,
            Int((Double(words) / LeadReplyPromptBuilder.readingWordsPerMinute) * 60)
        )
    }

    /// Three angles the composer covers. Stored as a String enum so
    /// SwiftUI's `ForEach` + the JSON decoder both round-trip on the
    /// same raw values.
    public enum Angle: String, Sendable, Codable, CaseIterable, Equatable {
        case direct
        case consultative
        case similarCase
    }
}
