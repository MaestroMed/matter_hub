import Foundation
import SwiftData

/// v1.0-alpha.2 — Cockpit Studio data spine.
///
/// A `Project` is a long-lived client engagement. In Mehdi's actual
/// Numelite workflow that means one row per shipped Next.js site:
/// `AZ Construction`, `IEF & Co`, `Sconnect`, etc. Each Project owns
/// the contractual surface (stack, contract type, MRR / one-shot
/// revenue, lifecycle stage), the deployment surface (host, GitHub
/// repo, Vercel project ID), the lead-inbox surface (webhook secret +
/// the cascade-deleted `leads`), and the deliverable archive
/// (cascade-deleted `deliverables`).
///
/// Coexistence with `Node`
/// -----------------------
/// Wave A pivoted the UI to a 4-tab Cockpit but left the legacy
/// `Node` + `Edge` + `FocusSessionRecord` @Model classes in the
/// schema — the CloudKit daemon would have re-restored every module
/// we deleted anyway. The pivot is **additive** at the data layer:
/// Project / Lead / Deliverable land *alongside* Node, never in
/// place of it. Wave C will route HomeView + ProjectsView + Pipeline
/// onto these new models without breaking the existing `.client` /
/// `.audit` Node surface.
///
/// CloudKit constraints
/// --------------------
/// Same three constraints that govern `Node` apply here too:
///   1. Every non-optional stored property carries an inline default
///      so the CloudKit-backed persistent store can boot cleanly
///      ("CloudKit integration requires that all attributes be
///      optional, or have a default value set.")
///   2. `@Attribute(.unique)` on `id` survives only on Simulator —
///      CloudKit's ingest pipeline silently drops the constraint
///      with a warning at first sync. UUID() collision probability
///      (≈ 1 in 2^122) is the real uniqueness guarantee.
///   3. All to-many relationships (`leads`, `deliverables`) are typed
///      as optional arrays with a `nil` default; SwiftData auto-
///      instantiates the array on the first append. An empty-array
///      default would crash the CloudKit initializer at boot — same
///      lesson learned on `Node.outgoing` / `Node.incoming` during
///      v0.30's pipeline work.
@Model
public final class Project {
    @Attribute(.unique) public var id: UUID = UUID()

    /// Human-readable project name, surfaced in every Cockpit list
    /// row and in the Spotlight title. Examples from the seed:
    /// `AZ Construction`, `IEF & Co`, `Sconnect`.
    public var name: String = ""

    /// URL-safe identifier derived from `name` (lowercased, accents
    /// stripped, non-alphanumerics → `-`). Used inside repo names,
    /// Vercel project IDs, and the local Documents folder under
    /// `client-portals/<slug>-<date>/`. The seeded projects ship with
    /// the exact slugs the existing Numelite repos already use, so
    /// matching across surfaces stays trivial.
    public var slug: String = ""

    /// Production hostname the project is reachable at, without
    /// `https://` prefix. Drives the per-Project favicon fetch on
    /// the Cockpit cards. Empty string for projects still in
    /// discovery (no live site yet).
    public var host: String = ""

    /// GitHub `owner/repo` of the source. Optional because some
    /// engagements live on Vercel's git-less mode or under a private
    /// host (Bitbucket, GitLab). Stored as a plain string; the
    /// `https://github.com/...` URL is derived at presentation time.
    public var githubRepo: String?

    /// Vercel project identifier (the opaque string after `prj_`).
    /// Optional — non-Next.js or non-Vercel projects skip this. A
    /// future deploy-status widget will use it to call Vercel's API
    /// per project without re-prompting for a project ID at the
    /// call site.
    public var vercelProjectID: String?

    /// Raw stack identifier. Round-trips through `ProjectStack`
    /// via the computed accessor below; stored as a String for the
    /// same CloudKit-friendliness rationale that drives
    /// `Node.pipelineStageRaw`.
    public var stack: String = ProjectStack.nextjs.rawValue

    /// Raw contract type. `oneshot` covers the classic "ship a site
    /// for €N, hand it over" engagement; `retainer` covers the
    /// monthly-MRR maintenance subscription that follows. Round-trips
    /// through `ProjectContractType` via the accessor below.
    public var contractType: String = ProjectContractType.oneshot.rawValue

    /// Recurring revenue in euros, integer to dodge floating-point
    /// totals. `0` for any `oneshot` project (the accessor above
    /// is the authoritative discriminator — this field is free-form).
    public var monthlyRecurringRevenueEUR: Int = 0

    /// One-shot project value in euros. Mehdi's quoted price for
    /// the build phase, before any retainer kicks in.
    public var oneShotRevenueEUR: Int = 0

    /// Raw lifecycle stage. Discovery → active → maintenance →
    /// archived. Round-trips through `ProjectLifecycleStage`.
    public var lifecycleStage: String = ProjectLifecycleStage.active.rawValue

    /// When Mehdi first opened a Project row for this engagement.
    /// Distinct from the lead's `receivedAt`: a Project can predate
    /// any inbound lead (Mehdi prospected first), or post-date it
    /// (the lead was qualified before the Project was minted).
    public var startedAt: Date = Date.now

    /// Touched on every Lead receipt, every Deliverable creation, and
    /// every manual edit. Drives the "Récent" sort on the Cockpit
    /// Projects list — most-recently-touched projects float to the top.
    public var lastActivityAt: Date = Date.now

    /// Hex accent for the per-Project card chrome. Defaults to MIND's
    /// iris (`#5E5BD8`) so projects that don't override it inherit
    /// the same Liquid Glass tint as the rest of the app.
    public var primaryColor: String = "#5E5BD8"

    /// Free-form markdown notes Mehdi keeps per project: subdomain
    /// secrets, Cloudflare zone IDs, the email Sara from IEF prefers
    /// for invoices. Plain string, persists locally + via CloudKit.
    public var notes: String = ""

    /// HMAC-SHA256 shared secret the deployed site uses to sign the
    /// `/api/leads` webhook POST body. Optional because a Project
    /// may not yet have its site wired to MIND. When set, the
    /// `LeadWebhookPayload.verify(payload:signature:secret:)` helper
    /// uses it to gate inbound leads.
    public var webhookSecret: String?

    /// Master switch for the Lead inbox surface. Defaults to `true`
    /// because the whole point of a Project is that it accepts
    /// inbound leads — explicit opt-out for the rare archived /
    /// discovery-only project.
    public var leadInboxEnabled: Bool = true

    /// Cascade-deleted leads — when the user deletes a Project the
    /// matching Lead rows die with it. Optional `[Lead]?` with nil
    /// default for the same CloudKit-init reason as `Node.outgoing`.
    @Relationship(deleteRule: .cascade, inverse: \Lead.project)
    public var leads: [Lead]?

    /// Cascade-deleted deliverables — same rationale + same nil
    /// default for CloudKit compatibility.
    @Relationship(deleteRule: .cascade, inverse: \Deliverable.project)
    public var deliverables: [Deliverable]?

    /// v1.2.0 — Notion bidirectional sync. UUID-without-dashes
    /// identifier of the source Notion page when this Project was
    /// imported from Notion via `NotionImportExecutor`. nil for
    /// Projects that originated inside MIND or via the v1.0-alpha.11
    /// GitHub bulk-import wizard. Optional so existing CloudKit rows
    /// decode cleanly (the @Model migration is additive).
    public var notionPageID: String?

    /// v1.2.0 — Notion bidirectional sync. Timestamp of the last
    /// successful pull from Notion. The foreground bidirectional
    /// tick reads this + the Notion page's `lastEditedAt` to decide
    /// whether the row needs a re-pull.
    public var lastNotionSyncAt: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        host: String,
        slug: String? = nil,
        githubRepo: String? = nil,
        vercelProjectID: String? = nil,
        stack: ProjectStack = .nextjs,
        contractType: ProjectContractType = .oneshot,
        monthlyRecurringRevenueEUR: Int = 0,
        oneShotRevenueEUR: Int = 0,
        lifecycleStage: ProjectLifecycleStage = .active,
        startedAt: Date = .now,
        primaryColor: String = "#5E5BD8",
        notes: String = "",
        webhookSecret: String? = nil,
        leadInboxEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.host = host
        // Slug normalisation matches the host's domain by default
        // (no scheme, no www, replace dots with dashes) so the
        // computed identifier mirrors what the operator already
        // associates with the project. Caller can override.
        self.slug = slug ?? Project.normalizeSlug(name)
        self.githubRepo = githubRepo
        self.vercelProjectID = vercelProjectID
        self.stack = stack.rawValue
        self.contractType = contractType.rawValue
        self.monthlyRecurringRevenueEUR = monthlyRecurringRevenueEUR
        self.oneShotRevenueEUR = oneShotRevenueEUR
        self.lifecycleStage = lifecycleStage.rawValue
        self.startedAt = startedAt
        self.lastActivityAt = startedAt
        self.primaryColor = primaryColor
        self.notes = notes
        self.webhookSecret = webhookSecret
        self.leadInboxEnabled = leadInboxEnabled
    }

    // MARK: - Strongly-typed accessors

    /// Round-trips `stack` through the strongly-typed enum so call
    /// sites stop pattern-matching on raw strings. Unknown values
    /// fall back to `.other` (never crash a stored row).
    public var stackEnum: ProjectStack {
        get { ProjectStack(rawValue: stack) ?? .other }
        set { stack = newValue.rawValue }
    }

    /// Round-trips `contractType` through the strongly-typed enum.
    /// Unknown raw values fall back to `.oneshot` because that's the
    /// safer default for surfaced revenue math (a stray `retainer`
    /// would multiply MRR by 12 in a forecast).
    public var contractTypeEnum: ProjectContractType {
        get { ProjectContractType(rawValue: contractType) ?? .oneshot }
        set { contractType = newValue.rawValue }
    }

    /// Round-trips `lifecycleStage` through the strongly-typed enum.
    /// Unknown raw values fall back to `.active` so an unrecognized
    /// stage doesn't accidentally archive a live project on the UI.
    public var lifecycleStageEnum: ProjectLifecycleStage {
        get { ProjectLifecycleStage(rawValue: lifecycleStage) ?? .active }
        set { lifecycleStage = newValue.rawValue }
    }

    /// Touches `lastActivityAt` to `now`. Caller is responsible for
    /// `try? context.save()` afterwards. Idempotent.
    @MainActor
    public func touchActivity() {
        lastActivityAt = .now
    }

    // MARK: - Slug normalisation

    /// Pure helper exported so tests + call sites can derive the same
    /// slug deterministically. Steps:
    ///   1. Lowercased.
    ///   2. Diacritics folded ("Concept" stays, "Épée" → "epee").
    ///   3. Non-alphanumerics collapsed to single `-`.
    ///   4. Leading / trailing `-` trimmed.
    ///   5. Capped at 60 chars (Vercel project IDs cap at 64,
    ///      `<slug>-<date>` folder names need headroom).
    public static func normalizeSlug(_ input: String) -> String {
        let folded = input.folding(options: .diacriticInsensitive, locale: .init(identifier: "en"))
            .lowercased()
        // Walk codepoints once to avoid expensive regex round-trips.
        var output = ""
        var lastWasDash = false
        for scalar in folded.unicodeScalars {
            let ch = Character(scalar)
            if ch.isLetter || ch.isNumber {
                output.append(ch)
                lastWasDash = false
            } else if !lastWasDash && !output.isEmpty {
                output.append("-")
                lastWasDash = true
            }
        }
        while output.hasSuffix("-") { output.removeLast() }
        if output.count > 60 {
            output = String(output.prefix(60))
            while output.hasSuffix("-") { output.removeLast() }
        }
        return output
    }

    // MARK: - Bulk Import (v1.0-alpha.11)

    /// Idempotent insert-or-update of a `Project` from a bulk-import
    /// `BulkImportRecord` payload (slug + name + host + GitHub
    /// repo + primary color + stack). Looks up an existing Project
    /// by exact `githubRepo` match; if found, updates the columns
    /// the import path knows about (`host`, `primaryColor`, `stack`,
    /// `lastActivityAt`, `name` if currently blank). If not found,
    /// inserts a fresh row carrying those columns.
    ///
    /// Returns the (newly inserted or updated) Project so the caller
    /// can chain UI updates without re-fetching. Touches
    /// `lastActivityAt` on every call so the cockpit "Récent" sort
    /// floats freshly-imported projects to the top.
    ///
    /// Why this lives here rather than in BootstrapKit: the upsert
    /// reads + writes a SwiftData `@Model`, which means it has to be
    /// on `Project`'s host module. BootstrapKit's `BulkImportPlanner`
    /// stays pure (no SwiftData), and the wizard hands the matching
    /// `BulkImportRecord` to this method one row at a time.
    @MainActor
    @discardableResult
    public static func upsert(
        from record: BulkImportRecord,
        in context: ModelContext
    ) throws -> Project {
        let needle = record.githubRepo
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate<Project> { project in
                project.githubRepo == needle
            }
        )
        if let existing = try context.fetch(descriptor).first {
            if existing.name.isEmpty { existing.name = record.suggestedName }
            existing.host = record.suggestedHost
            existing.primaryColor = record.suggestedPrimaryColor
            existing.stack = record.stack.rawValue
            existing.lastActivityAt = .now
            try context.save()
            return existing
        }
        let project = Project(
            name: record.suggestedName,
            host: record.suggestedHost,
            slug: record.suggestedSlug,
            githubRepo: record.githubRepo,
            stack: record.stack,
            primaryColor: record.suggestedPrimaryColor
        )
        context.insert(project)
        try context.save()
        return project
    }

    // MARK: - Notion Import (v1.2.0)

    /// Idempotent insert-or-update of a `Project` from a freshly-
    /// pulled Notion page. Match resolution order:
    ///   1. notionPageID exact match — re-pulling the same Notion
    ///      page always lands on the same Project row.
    ///   2. githubRepo exact match — a Project imported via the
    ///      GitHub wizard gets enriched with notionPageID rather
    ///      than duplicated.
    ///   3. Slug exact match — second-line dedup for manually-
    ///      created Projects later linked to a Notion page.
    ///   4. Insert.
    @MainActor
    @discardableResult
    public static func upsert(
        notionPageID: String,
        title: String,
        host: String? = nil,
        notes: String? = nil,
        githubRepo: String? = nil,
        in context: ModelContext
    ) throws -> Project {
        let needleNotion = notionPageID
        let byNotion = FetchDescriptor<Project>(
            predicate: #Predicate<Project> { project in
                project.notionPageID == needleNotion
            }
        )
        if let existing = try context.fetch(byNotion).first {
            applyNotionUpdates(
                to: existing,
                title: title,
                host: host,
                notes: notes,
                notionPageID: notionPageID
            )
            try context.save()
            return existing
        }

        if let repo = githubRepo, !repo.isEmpty {
            let needleRepo = repo
            let byRepo = FetchDescriptor<Project>(
                predicate: #Predicate<Project> { project in
                    project.githubRepo == needleRepo
                }
            )
            if let existing = try context.fetch(byRepo).first {
                applyNotionUpdates(
                    to: existing,
                    title: title,
                    host: host,
                    notes: notes,
                    notionPageID: notionPageID
                )
                try context.save()
                return existing
            }
        }

        let derivedSlug = Project.normalizeSlug(title)
        if !derivedSlug.isEmpty {
            let needleSlug = derivedSlug
            let bySlug = FetchDescriptor<Project>(
                predicate: #Predicate<Project> { project in
                    project.slug == needleSlug
                }
            )
            if let existing = try context.fetch(bySlug).first {
                applyNotionUpdates(
                    to: existing,
                    title: title,
                    host: host,
                    notes: notes,
                    notionPageID: notionPageID
                )
                try context.save()
                return existing
            }
        }

        let project = Project(
            name: title,
            host: host ?? "",
            githubRepo: githubRepo
        )
        project.notes = notes ?? ""
        project.notionPageID = notionPageID
        project.lastNotionSyncAt = .now
        context.insert(project)
        try context.save()
        return project
    }

    /// Applies Notion fields onto an existing Project without
    /// overwriting non-Notion columns the user already curated
    /// (stack / contractType / revenue / accent colour stay put).
    @MainActor
    static func applyNotionUpdates(
        to project: Project,
        title: String,
        host: String?,
        notes: String?,
        notionPageID: String
    ) {
        if !title.isEmpty { project.name = title }
        if let host, !host.isEmpty { project.host = host }
        if let notes, !notes.isEmpty { project.notes = notes }
        project.notionPageID = notionPageID
        project.lastNotionSyncAt = .now
        project.lastActivityAt = .now
    }

    // MARK: - Demo seeding

    /// Idempotently seeds the 5 real Numelite projects so a fresh
    /// install lands on the Cockpit with Mehdi's actual portfolio
    /// instead of an empty list. The caller must gate on the flag
    /// `@AppStorage("mind.demo.seeded")` to avoid re-seeding after
    /// a wipe — this method does not write the flag itself.
    ///
    /// v1.0-alpha.11 — Also bails when any Project already exists
    /// (not just newly-seeded ones), so a user who imported via the
    /// new wizard never gets the 5 hardcoded clients reseeded on top
    /// of their own portfolio.
    ///
    /// Returns the number of projects inserted (0 when the seed has
    /// already run, projects already exist, or the wizard imported
    /// some).
    @discardableResult
    public static func seedDemoProjects(in context: ModelContext) -> Int {
        // Idempotency: bail if any Project already exists. The user
        // may have already wiped + re-imported manually OR ran the
        // bulk import wizard already; we never duplicate-seed.
        let descriptor = FetchDescriptor<Project>()
        if let existing = try? context.fetch(descriptor), !existing.isEmpty {
            return 0
        }
        let seeds: [Project] = [
            Project(
                name: "AZ Construction",
                host: "www.azconstruction.fr",
                slug: "az-construction",
                githubRepo: "MaestroMed/AZConstruction_v0",
                stack: .nextjs,
                contractType: .retainer,
                monthlyRecurringRevenueEUR: 290,
                oneShotRevenueEUR: 4800,
                lifecycleStage: .active,
                primaryColor: "#1F6FEB"
            ),
            Project(
                name: "AZ Epoxy",
                host: "www.az-epoxy.fr",
                slug: "az-epoxy",
                githubRepo: "MaestroMed/AZEpoxy_v0",
                stack: .nextjs,
                contractType: .retainer,
                monthlyRecurringRevenueEUR: 190,
                oneShotRevenueEUR: 3600,
                lifecycleStage: .active,
                primaryColor: "#F0883E"
            ),
            Project(
                name: "AZ Concept",
                host: "www.azconcept.fr",
                slug: "az-concept",
                githubRepo: "MaestroMed/AZConcept_v0",
                stack: .nextjs,
                contractType: .oneshot,
                monthlyRecurringRevenueEUR: 0,
                oneShotRevenueEUR: 5200,
                lifecycleStage: .maintenance,
                primaryColor: "#3FB950"
            ),
            Project(
                name: "IEF & Co",
                host: "www.iefandco.com",
                slug: "ief-and-co",
                githubRepo: "MaestroMed/IEFCo_v0",
                stack: .nextjs,
                contractType: .retainer,
                monthlyRecurringRevenueEUR: 350,
                oneShotRevenueEUR: 6400,
                lifecycleStage: .active,
                primaryColor: "#A371F7"
            ),
            Project(
                name: "Sconnect",
                host: "www.sconnect.fr",
                slug: "sconnect",
                githubRepo: "MaestroMed/Sconnect_v0",
                stack: .nextjs,
                contractType: .oneshot,
                monthlyRecurringRevenueEUR: 0,
                oneShotRevenueEUR: 7200,
                lifecycleStage: .active,
                primaryColor: "#FF7B72"
            ),
        ]
        for project in seeds {
            context.insert(project)
        }
        try? context.save()
        return seeds.count
    }
}

/// v1.0-alpha.11 — Bulk Import. Slim DTO the iOS bulk-import wizard
/// hands to `Project.upsert(from:in:)`. Mirrors the columns of
/// `ProjectHealthKit.RepoMetadata` without forcing GraphCore to
/// import ProjectHealthKit (which would create a circular dep —
/// ProjectHealthKit already imports GraphCore).
///
/// The wizard maps a `RepoMetadata` to a `BulkImportRecord` before
/// calling `upsert`. Anyone who wants to test `upsert` without
/// touching the network can construct a `BulkImportRecord` directly.
public struct BulkImportRecord: Sendable, Equatable {
    public let githubRepo: String          // "MaestroMed/AZConstruction_v0"
    public let suggestedSlug: String       // "az-construction"
    public let suggestedName: String       // "AZ Construction"
    public let suggestedHost: String       // "www.azconstruction.fr"
    public let suggestedPrimaryColor: String  // "#5E5BD8" default iris
    public let stack: ProjectStack

    public init(
        githubRepo: String,
        suggestedSlug: String,
        suggestedName: String,
        suggestedHost: String,
        suggestedPrimaryColor: String,
        stack: ProjectStack
    ) {
        self.githubRepo = githubRepo
        self.suggestedSlug = suggestedSlug
        self.suggestedName = suggestedName
        self.suggestedHost = suggestedHost
        self.suggestedPrimaryColor = suggestedPrimaryColor
        self.stack = stack
    }
}

/// v1.0-alpha.2 — Stack family the project is built on. Drives
/// per-stack tooling (deploy hook, lighthouse profile, lint command)
/// in future waves.
public enum ProjectStack: String, CaseIterable, Sendable, Codable {
    case nextjs
    case wordpress
    case shopify
    case staticSite
    case other
}

/// v1.0-alpha.2 — Whether the engagement is a one-shot build or a
/// retainer-style monthly subscription. Forecast math sums
/// `monthlyRecurringRevenueEUR * 12` for retainer and
/// `oneShotRevenueEUR` for oneshot.
public enum ProjectContractType: String, CaseIterable, Sendable, Codable {
    case oneshot
    case retainer
}

/// v1.0-alpha.2 — Where the project sits in its lifecycle. The
/// Cockpit "Active" filter pins to `.active` + `.maintenance`;
/// `.discovery` is the pre-sale state and `.archived` the post-
/// engagement tombstone.
public enum ProjectLifecycleStage: String, CaseIterable, Sendable, Codable {
    case discovery
    case active
    case maintenance
    case archived
}
