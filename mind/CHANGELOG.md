# MIND — CHANGELOG

All notable changes to MIND. Format: a one-line summary per
version, anchored to the ULTRAPLAN.md entry for the full detail.

## 1.0.0 — 2026-05-20 — Cockpit Numelite, TestFlight ready

First public release. 13 modules, 30+ features, 1083+ tests, zero
Swift 6 strict-concurrency warning. Three destinations green
(iOS Simulator, iOS device generic, Mac Catalyst). App Store
submission package drafted under `mind/AppStore/`.

Highlights bundled into 1.0:

- Real-time lead inbox (Cloudflare Worker → APNs → enriched card)
- One-tap full audit (14 parallel probes synthesised by Claude)
- Pipeline kanban projects (lead → discovery → build → live →
  maintenance)
- Stripe + PDF invoicing with sequential numbering
- Cinematic Client Portal HTML exported on every audit
- Generative before/after redesigns for prospects (GPT Image 2)
- ElevenLabs voice clone for pitch audio
- Battle Mode (radar competitor comparison)
- AI Sales Email + Follow-Up Sequences
- Notion + Linear sync
- Lock Screen widgets + audit Live Activity + Dynamic Island
- Apple Watch companion (3-tab: Leads / Focus / Portfolio)
- Vision Pro substrate (`VisionSpatialKit`, runtime install pending)
- App Shortcuts + Siri + Spotlight indexing
- iPad NavigationSplitView + Mac Catalyst toolbar + Stage Manager
- Private CloudKit sync, no data on our servers

Privacy manifest extended with audio data (ElevenLabs voice
upload) and lead contact PII (name / email / phone — on-device
only). Info.plist usage descriptions translated to FR.
`aps-environment` flipped to `production` for the Notification
Service Extension. Fastlane `:beta` lane upgraded with TestFlight
changelog read from `mind/AppStore/release_notes_<version>.fr.md`;
new `:sync_metadata` lane wraps `fastlane deliver` for listing-copy
sync without a binary upload.

See `mind/RELEASE_1.0.0.md` for the suggested git tag command.

## 1.0-alpha.20 — 2026-05-20 — TestFlight finalisation wave

Rolled into 1.0.0 commit. Privacy manifest extension, Info.plist FR
translation, fastlane :beta + :sync_metadata, App Store metadata,
Mac Catalyst + iOS device generic build verification, README rewrite,
ULTRAPLAN cleanup. The originally-scoped visionOS destinations flip
moved to backlog item 1.5 (waiting on the visionOS 26.5 simulator
runtime install).

## 1.0-alpha.19 — 2026-05-20 — Vision Pro spatial cockpit

`VisionSpatialKit` substrate + SwiftUI surface. Six new files under
`mind/Modules/VisionSpatialKit/Sources/` (SpatialRootView,
SpatialLeadsView, SpatialProjectsView, SpatialAuditTheater,
SpatialAuditTheaterImmersive, TheaterPlacement, SpatialTelemetryBridge).
13 FR/EN spatial strings, 11 new pure tests. `#if os(visionOS)`
gated so iOS host's compile path stays untouched.

## 1.0-alpha.18 — 2026-05-20 — ElevenLabs voice clone

`VoiceCloneKit` module + `VoiceCloneSetupSheet` 5-step flow + audit
pitch audio card + base64 inline in Client Portal HTML. 35 FR/EN
keys, 19 new tests.

## 1.0-alpha.17 — 2026-05-20 — Apple Watch companion

`MINDWatch` watchOS 11 target. 3-tab vertical-page cockpit (leads /
focus / portfolio) reading the shared App Group via the new
`WatchConnectivityBridge` actor. 12 FR/EN keys, 24 new tests.

## 1.0-alpha.16 — 2026-05-20 — iOS 26 Lock Screen widgets + StandBy

Five new widget surfaces in `MINDWidgets`: cockpit lock screen,
lead inbox, portfolio MRR, deployment status, StandBy dashboard.
28 new tests on `CockpitWidgetFormatter`.

## 1.0-alpha.15 — 2026-05-20 — Mac Catalyst polish (build + UI)

`FocusKit.ActivityKit` wrapped `#if !targetEnvironment(macCatalyst)`.
App + Module + Tests targets flipped to `[.iPhone, .iPad, .macCatalyst]`.
Extensions stay iOS-only via `condition: .when([.ios])`. RootView
gains a Catalyst-only `.toolbar`. Settings ships "Apparence Mac"
section.

## 1.0-alpha.14 — 2026-05-20 — APNs Notification Service Extension

NSE decorates lead pushes with `<contactName> · <projectName>` +
120-char truncated body + `lead.<projectID>` thread grouping.
`mind://lead/<UUID>` deep-link routing.

## 1.0-alpha.13 — 2026-05-20 — AI Reply Composer + Sales Velocity + auto-archive

Three pieces: AI Reply Composer in LeadDetailSheet (3 tone-tagged
variants), Sales Velocity dashboard (12-month MRR / 12-week leads /
4-week conversion), Project auto-archive heuristic
(`ProjectLifecycleHeuristic.dormantProjects`).

## 1.0-alpha.12 — 2026-05-20 — Mac Catalyst polish (substrate)

`MacToolbarAction` table + shortcut catalog + scene-storage keys +
dock-badge math substrate landed.

## 1.0-alpha.11 — 2026-05-20 — Bulk Import GitHub repos

`BootstrapKit` + `BulkImportPlanner` + repo summary types.
GitHub repos imported in bulk + tagged + auto-classified.

## 1.0-alpha.10 — 2026-05-20 — Repository-aware Audit

`AuditKit` extended to read source code (when GitHub token present),
detect framework + dependency drift + accessibility issues at the
source level.

## 1.0-alpha.9 — 2026-05-20 — Live Actions + portfolio KPI bar

Home gains the live-action bar (top of screen) + portfolio KPI bar
under the greeting. Live Actions persist across launches.

## 1.0-alpha.8 — 2026-05-20 — Vercel + GitHub live integration

`ProjectHealthKit`: Vercel client, GitHub client, Lighthouse probe,
on-disk cache, Keychain stores. ProjectDetail surfaces live status.

## 1.0-alpha.7 — 2026-05-20 — SEO Swarm Orchestrator

`SwarmKit` + zone catalog (200+ zones) + exporter + on-disk store.
Generates a tree of zone-specific landing pages from one prompt.

## 1.0-alpha.6 — 2026-05-20 — Bootstrap scaffolder

New-project wizard: pick stack, generate `package.json` + `next.config`
+ webhook handler + Cloudflare Worker template.

## 1.0-alpha.5 — 2026-05-20 — Cloudflare Worker template

`mind/tools/cloudflare-worker/` + `@mind/lead-webhook` SDK. Routes
inbound contact forms → APNs → MIND.

## 1.0-alpha.4 — 2026-05-20 — ProjectsView replaces ClientsView

ClientsView retired. ProjectsView is the canonical surface backed
by the new SwiftData `Project` model.

## 1.0-alpha.3 — 2026-05-20 — HomeView "Aujourd'hui" lead inbox

Home gains the lead inbox card showing the day's leads with contact
preview + project tag.

## 1.0-alpha.2 — 2026-05-20 — Project + Lead + Deliverable data spine

New SwiftData models: `Project`, `Lead`, `Deliverable`. Replaces the
generic `Node` for cockpit surfaces (Node stays for free-form notes).

## 1.0-alpha.1 — 2026-05-20 — Radical cleanup (Cockpit Studio pivot)

Deleted FocusKit / HealthInsights / Notes / Chat / RemindersKit /
CalendarKit / Capture modules. Narrowed `NodeKind` to `.client` +
`.audit` + `.project` + `.lead`. Stripped Widgets / ShareExtension /
MINDIntents to the cockpit-only surface. README + ULTRAPLAN banner
flipped to "Cockpit Studio".

## 0.x — 2026-05-20 — Second-brain era (pre-pivot)

See `mind/ULTRAPLAN.md` "Chapter 1" → "Chapter 3" for the per-version
log of the second-brain build (v0.2 → v0.30). Highlights:
ClientPortal generator, Live Audit Broadcasting, generative redesigns,
Battle Mode, ROI Calculator, AI Sales Email, Follow-Up Sequences,
Pipeline Kanban. All shipped, all preserved as the substrate the
cockpit pivot built on top of.
