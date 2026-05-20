import ProjectDescription

public enum Module: String, CaseIterable {
    case designSystem = "DesignSystem"
    case graphCore = "GraphCore"
    case notes = "Notes"
    case intelligence = "Intelligence"
    case settings = "Settings"
    case chat = "Chat"
    case capture = "Capture"
    case mindIntents = "MINDIntents"
    case focusKit = "FocusKit"
    case visualKit = "VisualKit"
    case auditKit = "AuditKit"
    case calendarKit = "CalendarKit"
    case healthInsights = "HealthInsights"
    case remindersKit = "RemindersKit"
    case notionKit = "NotionKit"
    case linearKit = "LinearKit"
    case clientPortalKit = "ClientPortalKit"
    case liveBroadcastKit = "LiveBroadcastKit"
    case outreachKit = "OutreachKit"
    case invoiceKit = "InvoiceKit"
    case bootstrapKit = "BootstrapKit"
    case swarmKit = "SwarmKit"
    case watchCaptureKit = "WatchCaptureKit"
    case visionSpatialKit = "VisionSpatialKit"
    case projectHealthKit = "ProjectHealthKit"

    public var bundleId: String {
        "app.mind.ios.\(rawValue.lowercased())"
    }

    public var path: Path {
        .relativeToRoot("Modules/\(rawValue)")
    }

    public var dependencies: [TargetDependency] {
        switch self {
        case .designSystem:
            return []
        case .graphCore:
            return []
        case .notes:
            return [
                .target(name: Module.graphCore.rawValue),
                .target(name: Module.designSystem.rawValue),
            ]
        case .intelligence:
            return [
                .target(name: Module.graphCore.rawValue),
            ]
        case .settings:
            return [
                .target(name: Module.designSystem.rawValue),
                .target(name: Module.intelligence.rawValue),
                .target(name: Module.visualKit.rawValue),
                // Needed so Settings → Danger Zone can reach
                // GraphCore.sharedContainer for the "Wipe all data"
                // action and SpotlightIndexer for "Reset Spotlight".
                .target(name: Module.graphCore.rawValue),
                // v0.9 — Settings owns the HealthInsights opt-in toggle
                // and calls HealthReader.requestAccess() when the user
                // enables it. Depending on HealthInsights here means we
                // never reach across module boundaries from RootView to
                // trigger the authorization sheet.
                .target(name: Module.healthInsights.rawValue),
                // v0.10 — Settings owns the Reminders sync opt-in toggle
                // and calls RemindersStore.requestAccess() on toggle-on
                // so the EventKit permission sheet appears as a direct
                // consequence of the user's tap.
                .target(name: Module.remindersKit.rawValue),
                // v0.11 — Settings owns the Notion sync section (paste
                // integration token, paste database ID, "Test sync"
                // button). Depending on NotionKit here means the token
                // save + validate flow stays inside the same view that
                // shows its green/red dot status.
                .target(name: Module.notionKit.rawValue),
                // v0.12 — Settings owns the Linear sync section (paste
                // personal API key, save+validate button with green/red
                // dot, team picker once the token validates). Same
                // co-location rationale as NotionKit.
                .target(name: Module.linearKit.rawValue),
                // v0.31 — Settings owns the new "Facturation" section
                // (Stripe Payment Link prefix, SIRET, IBAN, VAT, address,
                // "Test invoice" CTA that emits a sample PDF). Depending
                // on InvoiceKit here means the test-invoice path stays
                // inside the same view that surfaces the inputs.
                .target(name: Module.invoiceKit.rawValue),
                // v1.0-alpha.8 — Settings owns the new "Intégrations
                // dev" section (Vercel + GitHub personal tokens +
                // "Test connexion" buttons). Depending on
                // ProjectHealthKit here means the token save +
                // validate flow stays inside the same view that shows
                // its green/red dot status, mirroring the Notion /
                // Linear sections.
                .target(name: Module.projectHealthKit.rawValue),
            ]
        case .chat:
            return [
                .target(name: Module.designSystem.rawValue),
                .target(name: Module.graphCore.rawValue),
                .target(name: Module.intelligence.rawValue),
            ]
        case .capture:
            return [
                .target(name: Module.designSystem.rawValue),
                .target(name: Module.graphCore.rawValue),
                .target(name: Module.intelligence.rawValue),
            ]
        case .mindIntents:
            return [
                .target(name: Module.graphCore.rawValue),
                .target(name: Module.intelligence.rawValue),
                .target(name: Module.auditKit.rawValue),
            ]
        case .focusKit:
            return [
                .target(name: Module.graphCore.rawValue),
            ]
        case .visualKit:
            return [
                .target(name: Module.graphCore.rawValue),
                .target(name: Module.intelligence.rawValue),
                .target(name: Module.auditKit.rawValue),
            ]
        case .auditKit:
            return [
                .target(name: Module.graphCore.rawValue),
                .target(name: Module.intelligence.rawValue),
            ]
        case .calendarKit:
            // EventKit reader + lightweight CalendarEvent value type used
            // by the HomeView "Aujourd'hui" card. Depends on GraphCore so
            // the card can mint a .meeting Node from a tap, and on
            // DesignSystem so any future in-module UI can reuse Liquid
            // Glass tokens without reaching across the layering boundary.
            return [
                .target(name: Module.graphCore.rawValue),
                .target(name: Module.designSystem.rawValue),
            ]
        case .healthInsights:
            // HealthKit reader + pure WeeklySummary value type for the
            // HomeView "Cette semaine" card (v0.9). Depends on GraphCore
            // so a future tap → Node flow stays consistent with
            // CalendarKit, and on DesignSystem for the same layering
            // reason. The HealthKit framework itself is linked from the
            // module's source via `import HealthKit`, gated behind
            // `#if canImport(HealthKit)` so the module still compiles
            // on platforms without it.
            return [
                .target(name: Module.graphCore.rawValue),
                .target(name: Module.designSystem.rawValue),
            ]
        case .remindersKit:
            // v0.10 — Reminders bidirectional sync. Depends on GraphCore
            // because the sync engine projects task-shaped Nodes into
            // `NodeProjection` value types before diffing them against
            // the EventKit snapshots, and writes back the paired
            // `reminderExternalID`. EventKit is linked from the module
            // source via `import EventKit` (same model as CalendarKit's
            // EKEventStore usage).
            return [
                .target(name: Module.graphCore.rawValue),
            ]
        case .notionKit:
            // v0.11 — One-way MIND → Notion sync. Depends on GraphCore
            // for MINDTelemetry breadcrumbs (notion.token.saved /
            // notion.page.created / …) and on AuditKit for the
            // `AuditReport` value type the NotionPageBuilder consumes.
            // No DesignSystem dep — NotionKit is pure model + actor
            // client; the visible UI lives in Settings / App which
            // already link DesignSystem.
            return [
                .target(name: Module.graphCore.rawValue),
                .target(name: Module.auditKit.rawValue),
            ]
        case .linearKit:
            // v0.12 — Audit Quick Wins → Linear issues. Same dep shape
            // as NotionKit: GraphCore for MINDTelemetry breadcrumbs
            // (linear.token.saved / linear.issue.created / …) and
            // AuditKit for `AuditReport.QuickWin`, which the pure
            // `LinearIssueBuilder` consumes. The actor `LinearClient`
            // posts to https://api.linear.app/graphql; the UI lives in
            // Settings + AuditSheet which already link DesignSystem.
            return [
                .target(name: Module.graphCore.rawValue),
                .target(name: Module.auditKit.rawValue),
            ]
        case .clientPortalKit:
            // v0.21 — MIND Client Portal Generator. Turns any completed
            // `AuditReport` into a self-contained premium HTML static
            // site. Depends on AuditKit for the `AuditReport` value
            // type and on GraphCore for `MINDTelemetry` breadcrumbs
            // (clientPortal.generated / clientPortal.shared / …). No
            // DesignSystem dep — the output is HTML, not SwiftUI, and
            // every visual decision lives in the Liquid Glass HTML
            // template strings inline (gradients, backdrop-filter,
            // typography). The host App target invokes
            // `ClientPortalBuilder.generateSite(for:brand:)` to obtain
            // an in-memory `ClientPortalArchive`, then hands it to the
            // `PortalWriter` actor which writes every file to
            // `Documents/client-portals/<slug>-<date>/`.
            return [
                .target(name: Module.graphCore.rawValue),
                .target(name: Module.auditKit.rawValue),
            ]
        case .liveBroadcastKit:
            // v0.22 — Live Audit Broadcasting. Spawns a self-contained
            // static site under `Documents/live-broadcasts/<token>/`
            // (an `index.html` template + a `state.json` snapshot the
            // template polls every 800 ms). AuditController mirrors
            // every probe transition + the final synthesis to that
            // folder via a `LiveBroadcastSession` handle. Mehdi then
            // exposes the folder over `cloudflared tunnel` / `ngrok`
            // / `tailscale serve` / Vercel — no MIND backend required.
            //
            // Depends on AuditKit because the writer mirrors the
            // `ProbeKind` / `Phase` enums + the `AuditReport` value
            // type. Depends on GraphCore for `MINDTelemetry`
            // breadcrumbs (`liveBroadcast.created` / `liveBroadcast.
            // updated` / `liveBroadcast.closed` / `liveBroadcast.
            // failed`). No DesignSystem dep — the output is HTML and
            // CSS strings, not SwiftUI.
            return [
                .target(name: Module.graphCore.rawValue),
                .target(name: Module.auditKit.rawValue),
            ]
        case .invoiceKit:
            // v0.31 — Stripe Invoice Generator. Renders a branded
            // PDF invoice for a Won client, derives a Stripe Payment
            // Link from the user-configured prefix + amount, and
            // persists every issued invoice under
            // `Documents/invoices/<uuid>.json`. The sequential MIND
            // invoice number (MIND-YYYY-NNNN) is generated by an
            // actor-backed counter in the same folder.
            //
            // Depends on GraphCore for `MINDTelemetry` breadcrumbs
            // (`invoice.draft.created` / `invoice.pdf.exported` /
            // `invoice.sent` / `invoice.paid.marked` /
            // `invoice.relancer.opened`). Depends on DesignSystem so
            // any in-module SwiftUI helper (status badge styling,
            // currency formatters that mirror `LiquidPalette`) can
            // reuse Liquid Glass tokens without re-rolling them. PDF
            // rendering lives in `InvoicePDFRenderer` and links
            // `UIKit` for `UIGraphicsPDFRenderer` from the framework
            // source directly.
            return [
                .target(name: Module.graphCore.rawValue),
                .target(name: Module.designSystem.rawValue),
            ]
        case .bootstrapKit:
            // v1.0-alpha.6 — Bootstrap Scaffolder. Pure value types
            // + a script generator that turns a `BootstrapBlueprint`
            // (the wizard output) into a runnable bash script that
            // scaffolds a new Next.js client site from scratch
            // (gh repo create, write template files via heredocs,
            // git push, vercel link). Depends on GraphCore so the
            // module can emit `MINDTelemetry` breadcrumbs
            // (`bootstrap.script.generated` / `bootstrap.zip.built`)
            // and reuse `ProjectStack` from the existing data spine
            // — the wizard mirrors the same stack enum the rest of
            // the cockpit lists. Depends on DesignSystem so any in-
            // module SwiftUI helper (preview chip, color picker)
            // can reuse Liquid Glass tokens without re-rolling them.
            return [
                .target(name: Module.graphCore.rawValue),
                .target(name: Module.designSystem.rawValue),
            ]
        case .outreachKit:
            // v0.26 — AI Sales Email Generator. Generates 5 cold
            // email variants per prospect via the cloud LLM bridge,
            // each tagged with an angle (ROI / Quick win / Concurrent
            // / Funding / Question), and exports the chosen variant
            // to Mail.app via a `mailto:` URL.
            //
            // Depends on AuditKit because the prospect context folds
            // the `AuditReport` quick wins + hidden risks into the
            // prompt grounding, AND because the production
            // `CloudIntelligenceHandle.live` bridge already lives in
            // AuditKit (introduced by v0.25's ROIEstimator). Reusing
            // that handle means we never re-roll the MainActor hop
            // around `CloudIntelligence` — a single regression in
            // the bridge fixes both the ROI estimator and the email
            // generator. Depends on GraphCore for `MINDTelemetry`
            // breadcrumbs (`outreach.generation.started` /
            // `outreach.generation.completed` /
            // `outreach.generation.failed`). Depends on Intelligence
            // for `CloudIntelligence` itself — the `CloudIntelligenceHandle`
            // type lives in AuditKit but the underlying actor lives
            // in Intelligence, and the live factory references the
            // Intelligence type directly.
            return [
                .target(name: Module.graphCore.rawValue),
                .target(name: Module.auditKit.rawValue),
                .target(name: Module.intelligence.rawValue),
            ]
        case .watchCaptureKit:
            // v0.22.1 — Watch voice capture (pure substrate). Pure
            // value types + on-disk queue + transcript assembler +
            // Node-draft builder that the deferred watchOS App
            // surface (and the iPhone "simulate Watch capture" sheet
            // that ships ahead of it) write into. Depends on
            // GraphCore for `NodeKind` (the draft's `kind` is
            // `.capture`) and for `MINDTelemetry` breadcrumbs once
            // the live drain wires up (`watchCapture.queued` /
            // `watchCapture.folded` / `watchCapture.failed`). No
            // DesignSystem dep — the kit is pure data; the SwiftUI
            // surface lives in the App target.
            return [
                .target(name: Module.graphCore.rawValue),
            ]
        case .visionSpatialKit:
            // v0.25.1 — Vision Pro spatial layout (pure substrate).
            // Pure value types + layout math + on-disk store behind
            // the deferred visionOS App target — same model
            // v0.22.1 / v0.31.1 / v1.0-alpha.8 used: lock the data
            // shape now, plug the future RealityView surface in
            // without re-rolling the model. No GraphCore dep — every
            // anchor / panel is self-contained and doesn't reference
            // Node / Project. No DesignSystem dep — the future
            // SwiftUI surface lives in the visionOS App target.
            return []
        case .swarmKit:
            // v1.0-alpha.7 — SEO Swarm Orchestrator. Generates N
            // {service}×{zone} Next.js pages in batch via the cloud
            // LLM bridge, exports the result as a directory tree the
            // user drops in their Next.js repo. The orchestrator is
            // an actor that fans out 3 in-flight Claude requests at
            // a time and streams progress events back to the UI.
            //
            // Depends on AuditKit for the `CloudIntelligenceHandle`
            // bridge (reused from ROIEstimator / OutreachKit). Depends
            // on Intelligence so the live factory can reach
            // `CloudIntelligence` directly (same model as OutreachKit).
            // Depends on GraphCore for `MINDTelemetry` breadcrumbs
            // (`swarm.job.started` / `swarm.page.generated` /
            // `swarm.page.failed` / `swarm.job.completed`) and on
            // DesignSystem because the in-module helpers (page card
            // chips) reuse Liquid Glass tokens.
            return [
                .target(name: Module.graphCore.rawValue),
                .target(name: Module.auditKit.rawValue),
                .target(name: Module.intelligence.rawValue),
                .target(name: Module.designSystem.rawValue),
            ]
        case .projectHealthKit:
            // v1.0-alpha.8 — Vercel + GitHub + Lighthouse live integration.
            // Pulls deployment state from the Vercel API, recent commits
            // and repo stats from the GitHub API, and Lighthouse scores
            // from Google PageSpeed Insights. Per-project token storage
            // sits in `VercelTokenStore` + `GitHubTokenStore` Keychain
            // wrappers (same shape as `NotionTokenStore` and
            // `LinearTokenStore`), and the in-memory + on-disk
            // `ProjectHealthCache` (5 min TTL) prevents hammering the
            // upstream APIs every time ProjectDetailSheet opens.
            //
            // Depends on GraphCore for `MINDTelemetry` breadcrumbs
            // (`vercel.deployment.fetched` / `github.commits.fetched` /
            // `lighthouse.probe.completed`) and on DesignSystem so the
            // in-module helpers (status chips, score gauges) reuse the
            // Liquid Glass tokens. No AuditKit dep — the Lighthouse
            // probe is a thin re-derivation tailored for the cockpit
            // grid, not the full AuditReport pipeline.
            return [
                .target(name: Module.graphCore.rawValue),
                .target(name: Module.designSystem.rawValue),
            ]
        }
    }

    public func target() -> Target {
        .target(
            name: rawValue,
            destinations: .iOS,
            product: .framework,
            bundleId: bundleId,
            deploymentTargets: .iOS("26.0"),
            sources: ["Modules/\(rawValue)/Sources/**"],
            dependencies: dependencies,
            settings: .settings(base: [
                "SWIFT_VERSION": "6.0",
            ])
        )
    }
}
