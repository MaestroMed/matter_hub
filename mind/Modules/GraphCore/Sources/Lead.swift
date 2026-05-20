import Foundation
import SwiftData

/// v1.0-alpha.2 — Cockpit Studio data spine.
///
/// A `Lead` is one inbound message captured by a deployed client
/// site and posted to MIND via the `/api/leads` webhook contract
/// (see `LeadWebhookPayload`). One Lead row per form submission:
/// the visitor fills `/contact` or `/devis` on
/// `www.azconstruction.fr`, the deployed site signs the payload with
/// the Project's `webhookSecret`, MIND verifies, persists, and
/// surfaces the lead in HomeView's "Aujourd'hui" inbox (Wave C).
///
/// The model carries everything HomeView + the future ReplyDraft
/// surface need:
/// - WHEN it came in (`receivedAt`)
/// - WHERE the visitor was (`sourceURL`, `formType`)
/// - WHO (`contactName`, `contactEmail`, `contactPhone`)
/// - WHAT they wrote (`message`)
/// - The raw payload for forensics (`rawPayload`)
/// - Pipeline state (`status`, `statusUpdatedAt`, `statusReason`)
/// - The Claude-drafted reply (`draftReply`, edited before send)
/// - Spam-triage signals (`clientIPHash`, `userAgent`)
///
/// CloudKit constraints
/// --------------------
/// Inherits the same constraint set as `Project` and `Node`: inline
/// defaults on every non-optional stored property, `@Attribute(.unique)`
/// on `id` (effectively a Simulator-only constraint), and optional
/// relationships (`project: Project?`) with `nil` defaults.
@Model
public final class Lead {
    @Attribute(.unique) public var id: UUID = UUID()

    /// When the webhook landed in MIND. Server-side timestamp from
    /// the deployed site (the payload includes a `receivedAt` field
    /// the worker sets via its own clock) — distinct from the local
    /// device clock so a queued retry doesn't backdate the row.
    public var receivedAt: Date = Date.now

    /// Page URL the form sat on. Useful both for attribution
    /// ("which landing page converted?") and for forensics when
    /// debugging a form misfire.
    public var sourceURL: String = ""

    /// Raw form discriminator. Round-trips through `LeadFormType`
    /// via the computed accessor below. Stored as String so a future
    /// custom form (e.g. `"audit-request"`) doesn't require a model
    /// migration before it can land in the inbox.
    public var formType: String = LeadFormType.contact.rawValue

    /// Visitor's name as captured on the form. Empty string when
    /// the form didn't ask (some legal-page contact forms only
    /// collect email + message).
    public var contactName: String = ""

    /// Visitor's email. Treated as authoritative even though the
    /// form may not validate it — MIND surfaces a "verify email"
    /// chip on suspicious shapes in Wave C.
    public var contactEmail: String = ""

    /// Visitor's phone, optional because most contact forms make
    /// it optional too. Stored as a free-form string; no
    /// normalisation (`+33...`, `06 12...`, both round-trip
    /// unchanged) so the original wording survives.
    public var contactPhone: String?

    /// The actual message body. Plain text, can contain newlines.
    /// The HomeView card truncates at ~140 chars; the detail view
    /// renders the full string.
    public var message: String = ""

    /// Full JSON payload the webhook sent, archived verbatim. When
    /// MIND surfaces a "verify webhook" diagnostic it shows this
    /// alongside the recomputed signature so Mehdi can spot a
    /// payload-tampering issue at a glance. Also covers a future
    /// extension where the form posts unknown fields MIND should
    /// surface as a generic JSON dump.
    public var rawPayload: String = ""

    /// Raw lifecycle status. Round-trips through `LeadStatus` via
    /// the accessor below. Drives HomeView filters and the future
    /// "Won/Lost" weekly summary card.
    public var status: String = LeadStatus.new.rawValue

    /// Timestamp of the last status transition. Distinct from
    /// `receivedAt` because a lead can sit in `.new` for hours
    /// before Mehdi touches it.
    public var statusUpdatedAt: Date = Date.now

    /// Optional reason persisted alongside `.lost` / `.spam`
    /// transitions ("budget out of reach", "competitor signed").
    /// nil for `.new` / `.contacted` / `.qualified` / `.won` —
    /// those statuses don't need a justification.
    public var statusReason: String?

    /// Claude-generated draft reply, optional because not every
    /// lead triggers a draft (Wave C will gate draft generation
    /// behind an opt-in). When set, the HomeView card shows a
    /// "Brouillon prêt" chip; the detail view exposes the editor
    /// pre-populated with this string.
    public var draftReply: String?

    /// SHA-256 hex of the client IP, written by the webhook layer
    /// (never the raw IP — privacy-first). Used to dedup repeat
    /// posts from the same visitor and to triage spam waves where
    /// every payload shares an IP hash.
    public var clientIPHash: String?

    /// User-Agent string captured by the webhook. Helps triage
    /// "is this an actual visitor or a curl-driven scraper?".
    public var userAgent: String?

    /// The owning Project. Optional because a Lead can briefly
    /// exist before MIND has resolved its `projectID` — a stray
    /// payload pointing at an unknown project should be
    /// persisted-then-flagged rather than silently dropped.
    public var project: Project?

    public init(
        id: UUID = UUID(),
        receivedAt: Date = .now,
        sourceURL: String = "",
        formType: LeadFormType = .contact,
        contactName: String = "",
        contactEmail: String = "",
        contactPhone: String? = nil,
        message: String = "",
        rawPayload: String = "",
        status: LeadStatus = .new,
        statusUpdatedAt: Date = .now,
        statusReason: String? = nil,
        draftReply: String? = nil,
        clientIPHash: String? = nil,
        userAgent: String? = nil,
        project: Project? = nil
    ) {
        self.id = id
        self.receivedAt = receivedAt
        self.sourceURL = sourceURL
        self.formType = formType.rawValue
        self.contactName = contactName
        self.contactEmail = contactEmail
        self.contactPhone = contactPhone
        self.message = message
        self.rawPayload = rawPayload
        self.status = status.rawValue
        self.statusUpdatedAt = statusUpdatedAt
        self.statusReason = statusReason
        self.draftReply = draftReply
        self.clientIPHash = clientIPHash
        self.userAgent = userAgent
        self.project = project
    }

    // MARK: - Strongly-typed accessors

    /// Round-trips `status` through the strongly-typed enum. Unknown
    /// values fall back to `.new` because surfacing a freshly-arrived
    /// lead as "to review" is the safest assumption when an unknown
    /// status raw string shows up.
    public var statusEnum: LeadStatus {
        get { LeadStatus(rawValue: status) ?? .new }
        set {
            status = newValue.rawValue
            statusUpdatedAt = .now
        }
    }

    /// Round-trips `formType` through the strongly-typed enum.
    /// Unknown values fall back to `.other` so a future custom form
    /// surfaces in the generic "Autres formulaires" bucket rather
    /// than misrouting to `.contact`.
    public var formTypeEnum: LeadFormType {
        get { LeadFormType(rawValue: formType) ?? .other }
        set { formType = newValue.rawValue }
    }
}

/// v1.0-alpha.2 — Lifecycle of a Lead inside the Cockpit pipeline.
/// `.new` is the inbox state; `.contacted` means Mehdi has replied;
/// `.qualified` means it's worth pursuing; `.won` / `.lost` are
/// terminal outcomes; `.spam` is a soft-delete that excludes the
/// row from HomeView while keeping it on disk for forensics.
public enum LeadStatus: String, CaseIterable, Sendable, Codable {
    case new
    case contacted
    case qualified
    case won
    case lost
    case spam
}

/// v1.0-alpha.2 — Which form the lead originated from. `.contact`
/// + `.devis` are the two Numelite-standard forms; `.newsletter`
/// covers a future signup form; `.other` is the open-ended bucket.
public enum LeadFormType: String, CaseIterable, Sendable, Codable {
    case contact
    case devis
    case newsletter
    case other
}
