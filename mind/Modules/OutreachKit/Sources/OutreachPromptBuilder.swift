import Foundation
import AuditKit

/// v0.26 — Pure prompt assembly + response parsing for the
/// AI Sales Email Generator. Lives in its own namespace so every
/// test in `OutreachKitTests` exercises this path without ever
/// touching the network.
public enum OutreachPromptBuilder {
    /// Word-per-minute rate used to estimate per-variant read time
    /// for the card subtitle. 220 WPM matches the median reading
    /// speed for a B2B prospect skimming a cold email (Nielsen
    /// Norman 2024 benchmark).
    public static let readingWordsPerMinute: Double = 220

    // MARK: - Prompt

    /// Build the full prompt string Claude receives. Deterministic
    /// for identical inputs so the future "régénérer" CTA can hit a
    /// cache without surprising the user with a different output.
    public static func build(
        prospect: ProspectContext,
        sender: SenderProfile,
        variantCount: Int
    ) -> String {
        let clampedCount = max(1, min(10, variantCount))

        // Sender block — Mehdi's identity + tone instruction.
        let toneInstruction: String
        switch sender.voice {
        case .friendly:
            toneInstruction = "warm, conversational, casual French agency tone — use 'tu' where natural, short sentences, contractions ok, a touch of humour ok, never corporate boilerplate."
        case .direct:
            toneInstruction = "direct, no fluff, leads with the insight or the ask — short paragraphs, no apologies, no 'I hope this finds you well'."
        case .formal:
            toneInstruction = "formal French business register — use 'vous', full salutation, no contractions, polite but firm."
        }

        // Industry / trigger / contact lines — every one is optional
        // so the prompt degrades gracefully when Mehdi hasn't filled
        // in the form.
        let industryLine = prospect.industry?.trimmedNonEmpty
            .map { "- Industry: \($0)" }
            ?? "- Industry: infer from the host + audit persona"
        let triggerLine = prospect.recentTrigger?.trimmedNonEmpty
            .map { "- Recent trigger: \($0)" }
            ?? "- Recent trigger: none provided (skip the 'Funding' angle if no trigger exists)"
        let contactLine: String
        if let name = prospect.primaryContactName?.trimmedNonEmpty {
            if let role = prospect.primaryContactRole?.trimmedNonEmpty {
                contactLine = "- Primary contact: \(name) (\(role))"
            } else {
                contactLine = "- Primary contact: \(name)"
            }
        } else {
            contactLine = "- Primary contact: unknown — open with the company-level 'Hi team,' / 'Bonjour,'"
        }

        // Audit grounding — when present, fold the top 3 quick wins
        // + hidden risks + overall score so Claude can name concrete
        // findings. When absent, instruct Claude to pick a generic
        // industry-prior angle so the variants stay grounded.
        let auditBlock: String
        if let report = prospect.auditReport {
            let topWins = report.quickWins.prefix(3).enumerated().map { (idx, win) in
                "    \(idx + 1). \(escape(win.title)) — \(escape(win.detail))"
            }.joined(separator: "\n")
            let topRisks = report.hiddenRisks.prefix(2).map { risk in
                "    - [\(risk.severity.rawValue)] \(escape(risk.title))"
            }.joined(separator: "\n")
            let winsLine = topWins.isEmpty ? "    (no quick wins synthesised)" : topWins
            let risksLine = topRisks.isEmpty ? "    (no hidden risks synthesised)" : topRisks
            auditBlock = """
            Audit findings (use these to ground every variant):
              Overall score: \(report.scoring.overall)/100 (performance: \(report.scoring.performance), seo: \(report.scoring.seo), security: \(report.scoring.security), brand: \(report.scoring.brand), mobile: \(report.scoring.mobile))
              Persona: \(report.persona.label)
              Top quick wins:
            \(winsLine)
              Hidden risks:
            \(risksLine)
            """
        } else {
            auditBlock = """
            Audit findings: NONE — no audit has been run yet on this prospect.
            For variants that would normally name concrete audit findings, pivot to a high-level industry observation, a Stripe/Linear-style benchmark, or an open question. Never invent fake audit numbers.
            """
        }

        return """
        You are a cold-email copywriter for \(sender.name), a \(sender.title). Generate \(clampedCount) distinct cold email variants in \(sender.voice.rawValue) voice for the prospect below. Each variant must take a different angle — never repeat an angle across the \(clampedCount) variants.

        Prospect:
          - Name: \(prospect.clientName)
          - URL host: \(prospect.host)
        \(industryLine)
        \(triggerLine)
        \(contactLine)

        \(auditBlock)

        Sender voice: \(toneInstruction)
        Sign every email with: \(sender.signature)

        Angles available (pick \(clampedCount) distinct ones, never repeat):
          - "roi"        → lead with a € impact number (use audit findings when present, industry baseline otherwise).
          - "quickWin"   → name one concrete fix the prospect could ship this week, ideally pulled from the audit Quick Wins.
          - "competitor" → contrast the prospect with a named competitor in their space (e.g. for a fintech, mention Stripe / Qonto / Lydia; for a SaaS, mention Linear / Notion / Slack).
          - "funding"    → reference the recent trigger (funding round, new hire, product launch) — SKIP this angle if no trigger was provided above.
          - "question"   → open with a sharp question that hooks curiosity, no pitch in the first paragraph.

        Output rules:
          - Subject line: max 60 characters, no clickbait, no emoji, no ALL-CAPS words.
          - Body: 3-6 short paragraphs, max 130 words total per email, plain text only (no markdown, no HTML), single blank line between paragraphs.
          - Body must mention the prospect's company name at least once.
          - Body must end with one sentence-form call to action (e.g. "15 min cette semaine ?" / "Worth a quick look?"). Never multiple CTAs.
          - Sign with the sender signature on its own line.
          - Never fabricate metrics, never invent press quotes, never claim a customer the sender doesn't have.

        Reply STRICTLY with valid JSON, no backticks, no prose before or after, no markdown. Exact schema:

        {
          "variants": [
            {
              "subject": "<≤ 60 chars>",
              "body": "<3-6 paragraphs, plain text, ≤ 130 words>",
              "angle": "roi" | "quickWin" | "competitor" | "funding" | "question"
            }
          ]
        }

        Rules:
          - Exactly \(clampedCount) variants, each with a distinct angle.
          - No additional fields outside the schema. No text outside the JSON object.
        """
    }

    // MARK: - Response parsing

    /// Strip fenced-code wrappers Claude occasionally adds even when
    /// asked for raw JSON. Mirrors `ROIPromptBuilder.stripFences` so
    /// the two stay in lock-step.
    public static func stripFences(_ response: String) -> String {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }
        return trimmed
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// JSON shape the parser decodes the response into. Public so
    /// the test suite can build its own response strings.
    public struct Payload: Codable, Equatable, Sendable {
        public let variants: [Variant]

        public struct Variant: Codable, Equatable, Sendable {
            public let subject: String
            public let body: String
            public let angle: String

            public init(subject: String, body: String, angle: String) {
                self.subject = subject
                self.body = body
                self.angle = angle
            }
        }

        public init(variants: [Variant]) {
            self.variants = variants
        }
    }

    /// Decode the LLM response into a fresh `[OutreachEmail]`. Soft-
    /// fails to `[]` only when the response can't be decoded at all
    /// — partial decodes (e.g. 3 of 5 variants well-formed) keep
    /// the well-formed entries so the user sees something rather
    /// than nothing. Unknown angle strings fall back to `.question`
    /// rather than dropping the variant entirely.
    public static func parse(response: String) -> [OutreachEmail] {
        let raw = stripFences(response)
        guard let data = raw.data(using: .utf8) else { return [] }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return []
        }
        return payload.variants.map { variant in
            let angle = OutreachEmail.Angle(rawValue: variant.angle) ?? .question
            let words = variant.body.split(whereSeparator: { $0.isWhitespace }).count
            let seconds = max(10, Int((Double(words) / readingWordsPerMinute) * 60))
            return OutreachEmail(
                subject: variant.subject,
                body: variant.body,
                angle: angle,
                estimatedReadTimeSeconds: seconds
            )
        }
    }

    // MARK: - Helpers

    private static func escape(_ source: String) -> String {
        source
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }
}

private extension String {
    /// nil when the trimmed string is empty, the trimmed string
    /// otherwise. Mirrors the helper in `ROIEstimator` so the two
    /// prompt builders behave identically on blank-but-present
    /// inputs.
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
