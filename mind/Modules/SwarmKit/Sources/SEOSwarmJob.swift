import Foundation

/// v1.0-alpha.7 — SEO Swarm value types.
///
/// `SEOSwarmJob` is the unit of work submitted to
/// `SEOSwarmOrchestrator.run(_:intelligence:)`. It captures the
/// `services × zones` matrix the user picked in `SwarmWizardSheet`,
/// links back to the `Project` the pages belong to, and accumulates
/// generated `SwarmPage` rows as the orchestrator progresses.
///
/// The job is `Codable` so `SEOSwarmStore` can persist it under
/// `Documents/seo-swarm-jobs/<id>.json` — same shape contract as the
/// v0.29 `FollowUpStore`. The job is `Sendable` so the orchestrator
/// can hand it across actor isolation boundaries without copying.
public struct SEOSwarmJob: Sendable, Equatable, Codable, Identifiable {

    public let id: UUID

    /// Soft link back to the owning `Project`. The orchestrator does
    /// not validate that the Project still exists; an orphan job is
    /// harmless and surfaces a banner in the UI.
    public let projectID: UUID

    /// Snapshot of the project's display name at job creation time so
    /// the run-time progress sheet can render the title without
    /// reaching back into SwiftData. Keeps the orchestrator pure.
    public let projectName: String

    /// Snapshot of the project's host so the prompt builder and the
    /// exported JSON-LD can name the LocalBusiness consistently even
    /// after the project's host changes downstream.
    public let projectHost: String

    /// Ordered list of service slugs (e.g. `["verriere", "escalier"]`).
    /// The orchestrator iterates `services × zones` row-major.
    public let services: [String]

    /// Ordered list of zones to target. Each zone carries its own
    /// display name, department code, and (optional) population so the
    /// prompt builder can ground the copy locally.
    public let zones: [SwarmZone]

    public let createdAt: Date

    public var status: SwarmJobStatus

    public var generatedPages: [SwarmPage]

    /// Set when the orchestrator catches a network or auth error that
    /// took the whole job down. Per-page failures live in
    /// `generatedPages` (a failed page is simply absent + the failure
    /// counter is bumped by telemetry).
    public var errorMessage: String?

    public init(
        id: UUID = UUID(),
        projectID: UUID,
        projectName: String,
        projectHost: String,
        services: [String],
        zones: [SwarmZone],
        createdAt: Date = .now,
        status: SwarmJobStatus = .queued,
        generatedPages: [SwarmPage] = [],
        errorMessage: String? = nil
    ) {
        self.id = id
        self.projectID = projectID
        self.projectName = projectName
        self.projectHost = projectHost
        self.services = services
        self.zones = zones
        self.createdAt = createdAt
        self.status = status
        self.generatedPages = generatedPages
        self.errorMessage = errorMessage
    }

    /// Convenience: total number of pages the orchestrator will
    /// attempt to generate. Tests + the UI cost preview both call
    /// this rather than re-computing the cross-product inline.
    public var plannedPageCount: Int {
        services.count * zones.count
    }
}

/// v1.0-alpha.7 — One zone the swarm should target. Carries the slug
/// (URL-safe identifier used in the page route), a human-readable
/// display name, a French department code (used in titles +
/// LocalBusiness JSON-LD), and an optional population integer used by
/// the prompt builder to ground the copy.
public struct SwarmZone: Sendable, Equatable, Codable, Hashable {
    public let slug: String
    public let displayName: String
    public let departmentCode: String
    public let population: Int?

    public init(
        slug: String,
        displayName: String,
        departmentCode: String,
        population: Int? = nil
    ) {
        self.slug = slug
        self.displayName = displayName
        self.departmentCode = departmentCode
        self.population = population
    }
}

/// v1.0-alpha.7 — One generated SEO page. Holds the full payload the
/// `SEOSwarmExporter` later turns into a `page.tsx` for the user's
/// Next.js app router.
///
/// `tokensUsed` is the rough total of input + output tokens billed by
/// Claude for this page — surfaced in the run-time progress sheet so
/// the user sees the cost climbing in real time.
public struct SwarmPage: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    public let serviceSlug: String
    public let zoneSlug: String

    /// Page route under the project's domain, with leading slash
    /// (`/verriere/puteaux`). The exporter reuses this as the
    /// filesystem path under `src/app/`.
    public let route: String

    /// `<title>` and the rendered H1 of the page. Title is the more
    /// keyword-loaded variant ("Verrière Puteaux (92) — AZ Construction")
    /// while H1 is the conversational hook.
    public let title: String
    public let metaDescription: String
    public let h1: String

    /// Body of the page in plain Markdown. 1500-2500 words FR per the
    /// page prompt contract. The exporter wraps it in `<article>` and
    /// renders via the existing `MarkdownRenderer` on the Next.js side.
    public let bodyMarkdown: String

    /// `<script type="application/ld+json">` payload — LocalBusiness +
    /// Service + areaServed for the zone. Already serialised as a JSON
    /// string so the exporter can drop it straight into the template
    /// without re-marshalling.
    public let jsonLD: String

    public let generatedAt: Date
    public let tokensUsed: Int

    public init(
        id: UUID = UUID(),
        serviceSlug: String,
        zoneSlug: String,
        route: String,
        title: String,
        metaDescription: String,
        h1: String,
        bodyMarkdown: String,
        jsonLD: String,
        generatedAt: Date = .now,
        tokensUsed: Int = 0
    ) {
        self.id = id
        self.serviceSlug = serviceSlug
        self.zoneSlug = zoneSlug
        self.route = route
        self.title = title
        self.metaDescription = metaDescription
        self.h1 = h1
        self.bodyMarkdown = bodyMarkdown
        self.jsonLD = jsonLD
        self.generatedAt = generatedAt
        self.tokensUsed = tokensUsed
    }
}

/// v1.0-alpha.7 — Lifecycle of a swarm job. `.partial` covers the
/// soft-fail case where some (but not all) pages were generated; the
/// orchestrator never throws on a per-page failure but rolls the
/// whole job into `.partial` (or `.failed` if zero pages survived).
public enum SwarmJobStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case queued
    case running
    case completed
    case failed
    case partial
}
