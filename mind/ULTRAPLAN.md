# MIND — ULTRAPLAN v2 (50 versions)

> ⚠️ **MIND a pivoté (2026-05-20).** Le projet n'est plus un second-
> brain : c'est désormais un **cockpit Studio** pour l'agence Numelite
> — outil interne pour piloter sites clients, leads, projets et
> factures. Voir `v1.0-alpha.*` pour le nouveau scope. Les entrées du
> chapitre 3+ ci-dessous sont **préservées pour archéologie** ; la
> roadmap réelle vit désormais dans les versions `v1.0-alpha.x`.

# v1.0-alpha.* — Cockpit Studio rebuild

The Numelite cockpit needs its own data spine: `Project` (long-lived
client engagement), `Lead` (inbound webhook from the deployed site),
`Deliverable` (shipped page / audit / asset). Wave A pivoted the UI,
Wave B (v1.0-alpha.2) lands the SwiftData models, Wave C+ rewrites
the SwiftUI surfaces (Home / Projects / Pipeline) to consume them.

## v1.0-alpha.13+ — Next ⏳

- **v1.0-alpha.12.1** ⏳ — Mac Catalyst destination flip. Split
  `FocusKit.ActivityKit` (Live Activities) off so the App target
  can adopt `[.iPhone, .iPad, .macCatalyst]` cleanly, then turn on
  the Catalyst toolbar wiring + Touch Bar + the "Apparence Mac"
  Settings section the v1.0-alpha.12 substrate already locks.
- **APNs Notification Service Extension** ⏳ — server-side push
  decryption for the lead webhook so a webhook fired while MIND is
  off-device still rings the dock badge.
- **iOS 26 Lock Screen widgets** ⏳ — WidgetKit timeline reading
  the same lead inbox + portfolio KPI surface HomeView shows, gated
  on `WidgetFamily.accessoryRectangular` + `.accessoryInline`.
- **Watch companion app** ⏳ — already has the
  `WatchCaptureKit` substrate (v0.22.1); ship the
  `MIND Watch.app` target + the SFSpeech transcription drain.
- **AI Mehdi Voice clone (ElevenLabs)** ⏳ — voice-out for the
  Daily Brief / Reply assistant via the consultant's own voice.
- **Vision Pro spatial cockpit** ⏳ — already has the
  `VisionSpatialKit` substrate (v0.25.1); ship the visionOS App
  target + the RealityView spatial layout.

## v1.0-alpha.12 — Mac Catalyst polish (substrate) ✅

**What**: MIND has been iPhone-first. With the Cockpit Studio scope,
Mehdi will want to operate it on his 27" Numelite workstation with a
Magic Keyboard. This wave ships the pure substrate every Catalyst
surface reads from — toolbar action table, expanded keyboard
shortcut catalog (⌘B / ⌘L / ⌘I / ⌘R / ⌘P / ⌘, plus the ⌘⇧ project-
action quartet), `@SceneStorage` key namespace, dock-badge math —
together with the menu-bar wiring, `LSApplicationCategoryType`
declaration, and lifecycle telemetry. iPhone / iPad still build
clean and `host-launches-clean` on the iPhone 17 Pro simulator
matches the v1.0-alpha.10/11 vision-verify bar. The Catalyst slice
itself is deferred to v1.0-alpha.12.1 — `FocusKit.ActivityKit`
(Live Activities) is unavailable on Catalyst, so flipping the App
destinations to `[.iPhone, .iPad, .macCatalyst]` cascades compile
errors through the legacy AmbientView / FocusController graph that
needs splitting (or retiring alongside its Cockpit-pivot peers).
The substrate is sized to make 12.1 a destination-flip + module-
membership tweak, nothing more.

Shipped 2026-05-20: new pure-data substrate `MacCatalystSupport.swift`
in `mind/App/Sources/` ships three independently-testable Sendable
types — `MacToolbarAction` (4 cases: leads / audit / bootstrap /
refresh; each with stable rawValue used as Notification.Name,
localizedKey under `toolbar.<rawCaseName>`, SF Symbol systemImage,
FR/EN fallback title for unit-test bundles); `MacShortcut` (11
cases: bootstrap/leadInbox/newInvoice/refresh/pipelineTab/
settingsTab/focusSearch/auditSource/battleMode/outreach/deploy,
each with key Character + `Modifiers` Sendable struct {command,
shift}, dedicated `Notification.Name` under
`app.mind.ios.command.*` namespace, `notificationUserInfo` payload
for the ⌘P / ⌘, tab-switch entries that reuse `.mindCommandSelectTab`,
`localizedKey` under `menu.shortcuts.<rawValue>`, fallback title);
`MacSceneStorageKey` (4 namespaced string constants:
`mind.scene.{selectedTab,selectedProjectID,selectedLeadID,sidebarVisibility}`
+ `allKeys` array for the namespace audit test);
`MacDockBadge.displayCount(forNewLeads:)` (pure clamp, 0...99,
prevents a 1247-lead webhook flood from rendering nonsense on the
dock icon). Nine new Notification.Name file-scope constants added
(`mindCommandLeadInbox`, `mindCommandAuditToolbar`,
`mindCommandBootstrap`, `mindCommandRefresh`, `mindCommandNewInvoice`,
`mindCommandFocusSearch`, `mindCommandAuditSource`,
`mindCommandBattleMode`, `mindCommandOutreach`, `mindCommandDeploy`)
— every channel is `app.mind.ios.command.*`-namespaced so a sweep
test catches drift.

`StageManagerCommands.swift` (the SwiftUI `Commands` builder
mounted on `MINDApp.swift`'s WindowGroup) gains 11 new menu entries
across three CommandGroup placements: `.newItem` cluster gets ⌘B
(Bootstrap), ⌘I (New Invoice); a new `.pasteboard`-after group
gets ⌘L (Lead inbox), ⌘R (Refresh), ⌘F (Focus search); the View
`CommandMenu` keeps ⌘1...⌘4 + adds ⌘P (Pipeline), ⌘, (Settings —
mac preferences convention); a new "Project" `CommandMenu` adds
⌘⇧A (Audit source code), ⌘⇧B (Battle Mode), ⌘⇧E (Reply assistant),
⌘⇧D (Redeploy). Every menu pick posts on a uniquely-namespaced
Notification.Name AND fires a `mac.shortcut.fired` telemetry
breadcrumb with the key-equivalent payload (e.g. `cmd-shift-a`),
so we can read the menu-bar adoption rate per shortcut from Sentry
without instrumenting each listener.

`Project.swift` adds `LSApplicationCategoryType =
"public.app-category.productivity"` to the App target's InfoPlist
so the Mac App Store bundle reads cleanly the moment the Catalyst
destination flag flips in 12.1. The App `destinations` itself
stays `.iOS` — the file-level comment documents the FocusKit /
ActivityKit blocker and what 12.1 needs to land.

`MINDApp.swift` gains a `refreshDockBadge()` method gated by
`#if targetEnvironment(macCatalyst)` that reads the new-Lead count
via SwiftData FetchDescriptor + clamps through
`MacDockBadge.displayCount(forNewLeads:)` + writes via
`UNUserNotificationCenter.setBadgeCount(_:withCompletionHandler:)`
(the iOS 16+ API that handles both the iPhone home-screen icon
badge and the Catalyst dock badge cleanly). The
`.onChange(of: scenePhase)` block emits the four new telemetry
breadcrumbs (`mac.scenePhase.active/background/inactive` +
`mac.dockBadge.updated` from the foreground path).

Localizable.xcstrings adds 20 new FR/EN keys under three
namespaces: `menu.project.menu` + 11 × `menu.shortcuts.*` (every
MacShortcut case + 4 standalone tab-switch labels), 4 × `toolbar.*`
(every MacToolbarAction case), 3 × `settings.mac.*` (the
"Apparence Mac" section MINDPreferences ships behind in 12.1),
1 × `mac.dockBadge.leads.format` (accessibility label for the
dock badge with %d count placeholder).

Tests: 18 new tests across three pure-substrate test files —
9 `MacKeyboardShortcutsTests` (⌘B / ⌘L / ⌘I individual mapping
locks, unique (key, modifier-set) tuple contract,
`app.mind.ios.command.*` namespace prefix sweep, ⌘P / ⌘, payload
contract, ⌘⇧ project-action modifier convention, NotificationCenter
post round-trip, `menu.shortcuts.*` localizedKey namespace);
5 `MacToolbarTests` (every action has title + systemImage +
fallback, toolbar.* localizedKey namespace, `app.mind.ios.command.*`
rawValue namespace, notification name ↔ rawValue alignment,
uniqueness of notification names across the table);
4 `MacSceneStorageTests` (allKeys count + membership locks,
`mind.scene.*` namespace sweep, key uniqueness, dock-badge
clamp range over -5/0/1/12/99/100/9999). `LocalizationTests`
extended with `test_macCatalystStrings_resolveBothLanguages`
(20+ FR + EN asserts including the `%d` placeholder survival
in `mac.dockBadge.leads.format`). 933 tests total, 19 skipped,
0 failures (was 916 in v1.0-alpha.11). Build SUCCEEDED on
iPhone 17 Pro simulator. Vision verify at
`mind/screenshots/v1.0-alpha.12.png` — host launches clean on
the cockpit Home with greeting + KPI bar + Boîte leads (4 demo
leads visible) + Projets actifs carousel + LiquidTabBar pinned.
The Catalyst-only surfaces (menu bar, dock badge, toolbar) only
render when running under Catalyst, matching the documented
host-launches-clean vision-verify bar.

## v1.0-alpha.11 — Bulk Import GitHub repos ✅

**What**: Today MIND seeds 5 hardcoded clients (`AZ Construction`,
`AZ Epoxy`, `AZ Concept`, `IEF & Co`, `Sconnect`) on first launch.
Mehdi has 13+ real client repos on his GitHub. This wave replaces
the seed path with a real wizard: GitHub API enumerates every repo
the user owns, fans out parallel framework detections, surfaces a
review step with default-accepted "Recommandés" (Next.js / WordPress
/ Shopify / static) and default-off "Ignorés" rows with reasons,
then loops the accepted rows through `Project.upsert(from:in:)` so
re-running the wizard never duplicates a row.

Shipped 2026-05-20: new value types `GitHubRepoSummary` /
`RepoStackDetection` / `RepoMetadata` in
`mind/Modules/ProjectHealthKit/Sources/GitHubClient.swift` carrying
the slim columns the wizard needs (fullName, name, description,
isPrivate, defaultBranch, pushedAt, homepageURL, stars, topics for
the summary; framework + version + confidence + signals for the
detection; slug + name + host + primary color + detection + summary
for the metadata). Three new actor methods on the existing
`GitHubClient`: `listMyRepos(limit:)` (`GET /user/repos?per_page=N
&sort=pushed`), `detectStack(repo:)` (Contents API + recursive tree
walk; decision tree: `next` in deps → nextjs/0.95, `composer.json`
+ `wp-content/` → wordpress/0.9, `wp-content/` alone → wordpress
/0.7, `theme.liquid` → shopify/0.9, `_config.yml` or `mkdocs.yml` →
static/0.8, else other/0.3), `extractMetadata(repo:)` (orchestrator
that folds summary + detection + derived slug/name/host/color). New
pure helper `nextDependencyVersion(in:)` strips `^/~/>=` from the
`package.json` `next` dep so the version surfaces clean.

New pure module-level decider `BulkImportPlanner.plan(repos:detections:)`
in `mind/Modules/BootstrapKit/Sources/BulkImportPlanner.swift`
(BootstrapKit gains a ProjectHealthKit dep — no circular dep,
ProjectHealthKit doesn't import BootstrapKit). Output type
`BulkImportPlan` has `recommendedImports: [PlannedImport]` (every
row with `framework in {nextjs, shopify, wordpress, static}` AND
`confidence >= 0.5`, sorted by stars desc, default-accepted true)
and `skippedRepos: [SkippedRepo]` (everything else, each carrying
a FR sentence `"Framework non supporté (other, confiance 0.32)"`).
Duplicate input fullNames collapse to the first occurrence.

New SwiftUI surface `BulkImportSheet.swift` in `mind/App/Sources/`:
3-step wizard (scan / review / import), Liquid Glass tokens
throughout. Step 1 loads `listMyRepos` then fans out `detectStack`
with a 5-in-flight cap (manual TaskGroup gate). Step 2 renders two
LiquidCard sections (recommended + skipped) with per-row toggles,
framework badge tinted iris/aqua/green/orange/secondary, confidence
percentage pill, expand-to-show-detail interaction. Step 3 loops
the accepted rows through `Project.upsert(from:in:)` with a linear
progress bar and a "%d projets importés ✓" success toast.

New SwiftData helper `Project.upsert(from: BulkImportRecord, in:
ModelContext) throws -> Project` in `mind/Modules/GraphCore/Sources/
Project.swift`. Look-up by exact `githubRepo` match (`#Predicate`);
existing row → updates host / primaryColor / stack / lastActivityAt
+ name-if-empty; not found → mints a new row with the suggested
columns. Same-input re-run is a no-op apart from `lastActivityAt`.
A new `BulkImportRecord` value type lives in GraphCore (mirrors
`RepoMetadata`'s shipping columns without forcing GraphCore to
depend on ProjectHealthKit).

OnboardingView gains a 5th page between Notifications and Ready:
"Tes projets" + "Connecte ton GitHub pour importer tous tes projets
clients automatiquement." + a "Connecter GitHub" CTA that flips the
host's `showBulkImport` state. Skip-able — the user can still add
projects manually later. SettingsView gains an "Importer mes repos"
button below the GitHub PAT row, disabled while the token field is
empty.

`Project.seedDemoProjects(in:)` gains a tighter guard: bails when
ANY Project already exists (not just when its own previous run
already inserted), so a user who imported via the new wizard never
sees the 5 hardcoded clients reseeded on top of their portfolio.

26 new FR/EN xcstrings keys under the `onboarding.bulkImport.*` /
`bulkImport.*` / `settings.github.import.*` namespaces (title, step
labels, scan loading format, empty state, recommended / skipped
section titles, skip reason format, "Importer quand même" CTA,
review CTA format, import progress format, success toast format,
framework labels for the 5 buckets, confidence pill format, missing
token error).

9 new MINDTelemetry breadcrumbs: `bulkImport.opened`,
`bulkImport.scan.started` (with `repoCount`), `bulkImport.scan.
completed` (with `recommended` + `skipped` counts), `bulkImport.scan.
failed` (with `reason` or `error`), `bulkImport.review.accepted.
count`, `bulkImport.import.started` (with `count`),
`bulkImport.project.created`, `bulkImport.project.updated`,
`bulkImport.import.completed` (with imported + errors).

Tests: 6 new `GitHubRepoSummaryTests` (Codable round-trip fully
populated, Codable round-trip with nil description/homepage, equal
on identical fields, unequal on diff stars, preserves private flag,
preserves topics order). 5 new `RepoStackDetectionTests` (Codable
round-trip, Codable nil version round-trip, `nextDependencyVersion`
extracts + cleans caret prefix, returns nil when next absent,
equatable on identical fields). 10 new `RepoMetadataDerivationTests`
(`AZConstruction_v0` → `az-construction` slug, underscore →
dash, trailing non-alnum trimmed, `IEFandCo_v0` → `ie-fand-co`
slug, `AZConstruction_v0` → `AZ Construction` name, `IEFandCo_v0`
→ `IE Fand Co` name, already-spaced preserved, host from
homepage cleaned, host without homepage falls back to
`<slug>.vercel.app`, hex in description surfaces unchanged, no
hex → default iris). 12 new `BulkImportPlannerTests` (empty
→ empty plan, confidence 0.5 inclusive boundary, below 0.5 skipped,
all-nextjs high-confidence all-recommended, wordpress + static
recommended, "other" skipped, skip reason includes framework +
confidence, stars-desc ordering, deterministic for same input,
mixed frameworks bucketed, duplicates collapse). 6 new
`ProjectUpsertTests` (insert when missing, update when present,
idempotent on identical input, returns live ref, distinct repos
both insert, refreshes lastActivityAt).

## v1.0-alpha.10 — Repository-aware Audit (source code analysis) ✅

**What**: Today AuditKit's 13 probes audit the deployed URL: PageSpeed,
security headers, TLS, App Store, etc. They learn nothing about the
**code** behind the site. A consultant auditing a client's Next.js repo
needs source-level signals: outdated deps, missing CI, security smells,
bundle bloat, TypeScript strict on/off, test framework presence. This
wave adds a 14th probe (`RepositoryAuditProbe`) that reads the repo via
the GitHub Contents API + the recursive git tree, races up to 25 npm
registry calls in a TaskGroup for outdated-dep detection, and folds the
result into the existing `AuditReport.repoFindings` slot. The AuditSheet
"Code source" section + the portal HTML "Audit code source" band both
render the new grade letter + per-signal lists. ProjectDetailSheet
gains an "Auditer le code source" action that fires the probe directly
without the 13-probe URL flow, surfacing the result via a new
`RepoAuditDetailSheet`.

Shipped 2026-05-20: new `RepositoryAuditFindings` Sendable Codable
Hashable value type in `mind/Modules/AuditKit/Sources/` carrying
`packageManager` / `framework` / `typescriptStrict` /
`totalDependencies` / `outdatedDependencies` / `securitySignals` /
`ciSignals` / `testCoverage` / `bundleSignals` / `overallGrade` /
`summary`, plus nested `OutdatedDependency`, `SecuritySignal`,
`CISignals`, `TestCoverageSignals`, `BundleSignals` value types.
`RepoAuditGradeBuilder` (pure) maps the signals onto an A+ .. F
letter grade following the v1.0-alpha.10 rubric (F = `.env` in repo
or hardcoded secret suspect, D = no TS or 2+ high security signals,
C = missing CI or 6+ outdated deps or 1 high signal, B = missing
tests with CI present or 3-5 outdated with at least one major-behind,
A = one minor blemish, A+ = clean across the board) and renders a
3-bullet markdown summary. `NpmRegistryClient` actor wraps
`https://registry.npmjs.org/<pkg>/latest` with a 24h on-disk cache
under `Documents/npm-cache/` (soft-fail on every error). The probe
itself reads `package.json` + `tsconfig.json` + `.github/workflows/`
listing + the full recursive git tree via the GitHub Contents API
(new `readFile(repo:path:)` / `listDirectory(repo:path:)` /
`recursiveTree(repo:branch:)` helpers added to the existing
`GitHubClient` actor in ProjectHealthKit). AuditKit gained a
ProjectHealthKit dependency in `Tuist/ProjectDescriptionHelpers/Module.swift`
(no circular dep — ProjectHealthKit doesn't import AuditKit).

`AuditClient` gains an optional `githubRepo` field (backward-compatible
Codable). `AuditController` gains a 14th `.repoAudit` `ProbeKind` that's
only seeded into `probeStates` when the client carries a non-empty
`githubRepo` (the row stays out of the AuditSheet list for URL-only
audits, vs being a perma-failing red dot), a new
`activeProbeKinds(for:)` static helper that the seeding + retry path
read, and a new `runRepoFindings` slot on the parallel runner that
folds the result onto the synthesised `AuditReport.repoFindings`
(also backward-compatible Codable). `AuditSheet` gains a `repoSection`
mounted between Synthèse and Vision when `report.repoFindings != nil`
— a grade pill (LiquidPalette tier mapping iris/green/amber/orange/red
for A+/A/B/C/D, red shadow for F), framework subtitle, 3-bullet
summary, outdated-deps list (compact, with "majeur(s) derrière" badge
for any non-zero `majorBehind`), security signals list with severity
color dots, and a quick rows card covering CI / tests / bundle. The
client portal HTML template ships a parallel "Audit code source"
section with a 96px CSS grade letter centerpiece + mini-table of
outdated deps + severity-tagged signal list + CI/tests/bundle quick
rows, all wrapped in fresh `.repo__*` styles inside `inlineCSS(brand:)`.

`ProjectDetailSheet` gains a `repoAuditRunning` / `repoAuditResult`
state pair driving a new "Auditer le code source" action row (only
shown when `project.githubRepo` is non-empty) that fires
`RepositoryAuditProbe.shared.run(repo:)` directly and presents the
result inline via the new `RepoAuditDetailSheet` (mounted at
`mind/App/Sources/RepoAuditDetailSheet.swift`, reusing the AuditSheet
rendering vocabulary). 20 new FR/EN xcstrings keys land under the
`audit.section.repo.*` / `project.action.auditRepo` / `repo.audit.empty.token`
namespaces. 5 new MINDTelemetry breadcrumbs (`repoAudit.started`,
`repoAudit.completed` with grade payload, `repoAudit.outdated.count`,
`repoAudit.security.signals.count`, plus the existing
`audit.probe.failed` route for the wrapped runProbe call).

Tests: 6 new `RepositoryAuditFindingsTests` (defaults all-nil-or-zero,
Codable round-trip all optionals nil, Codable round-trip all fields
populated, `OutdatedDependency` Codable + Equatable, `SecuritySignal`
filePath optional, AuditReport decodes without repoFindings on legacy
payloads). 12 new `RepoAuditGradeBuilderTests` covering every grade
boundary: A+ for fully clean, A for one minor blemish, B for missing
tests with CI, B for 3 outdated with major, C for missing CI, C for
6+ outdated, D for no TypeScript, F for .env in repo, F for hardcoded
secret, plus summary has-three-bullets, summary-mentions-framework,
summary-is-deterministic. 5 new `NpmRegistryClientTests` (latestURL
shape, scoped-package URL, empty/whitespace nil, cache-key scoped
slash → `_` collapse, `NpmPackageInfo` Codable with and without size).
8 new `RepositoryAuditProbeTests` on the pure parsers (parsePackageJSON
inferred framework + package manager from Next.js / pnpm payload,
malformed input returns default PackageInfo, tsconfig JSONC + strict
detection, strict false / missing / nil paths, classifyWorkflows
detects test + deploy via filename keywords, detectSecuritySignals
trips env-in-repo high signal while sparing .env.example,
isNodeEngineStale boundary at Node 18, majorVersion strips operators).
Build SUCCEEDED on iPhone 17 Pro simulator. Vision verify at
`mind/screenshots/v1.0-alpha.10.png` shows the host launching clean
on the Cockpit — the Repo Audit surface itself lives behind the
ProjectDetail tap + "Auditer le code source" action, matching the
host-launches-clean vision-verify bar used by v1.0-alpha.8 /
v1.0-alpha.9 for on-demand UI.

## v1.0-alpha.9 — Live Actions + portfolio KPI bar ✅

**What**: Light up the live actions everywhere the cockpit shows
projects — not just in ProjectDetail. ProjectDetailSheet's Actions
section gains 5 new live rows ("Redeploy production" with
confirmation alert + toast, "Open site", "Open repo", "Open Vercel
dashboard", "Share client portal") each guarded behind a Vercel /
GitHub / portal-folder availability check so the row soft-empties
rather than throwing. HomeView gets a 4-cell portfolio KPI bar
(leads / active projects / builds in progress / errors 24h) driven
by a new `PortfolioHealthAggregator` actor that rolls up the
per-project `ProjectHealthCache` bundles. Tap the bar → opens a new
`PortfolioHealthSheet` with a per-project status table.
ProjectsView gets pull-to-refresh; HomeView gets pull-to-refresh;
both fan out fresh Vercel fetches via the aggregator's parallel
fetcher (5 in-flight max, soft-fail per project). ProjectCard gets
a deployment pill in its top-right corner that reads
READY / BUILD / ERROR from the cached bundle without burning fresh
API calls on the list view. NewProjectSheet picks up a Vercel
Project ID field so new projects can light up the live surface
immediately. Settings's "Test connexion" buttons replace the
hardcoded test with a real project-scoped check when a project
with a `vercelProjectID` exists, fall back to the lightweight
`/v2/user` ping otherwise.

Shipped 2026-05-20: new `PortfolioHealthAggregator` actor in
`ProjectHealthKit` with `snapshot(for:)` + `refreshAndSnapshot(for:)`
+ pure `reduce(bundles:totalActiveProjects:now:)` reducer (the
TaskGroup fan-out caps in-flight Vercel calls at 5 via a `ParallelGate`
semaphore actor, soft-fails per project, then rolls up into the
new `PortfolioHealth` Sendable value type with `buildsInProgress`
counting `BUILDING/QUEUED/INITIALIZING`, `buildErrors24h` gating on
a 24h window, `avgLighthousePerf` rounded mean across projects with
a cached `LighthouseScore`). `VercelClient` gains
`redeploy(projectID:projectName:githubRepo:branch:)` POSTing
`/v13/deployments` with `{name, gitSource:{type:"github",repo,ref},
target:"production"}` plus pure helpers `redeployURL()` +
`redeployBody(projectName:githubRepo:branch:)`.

`ProjectDetailSheet.swift` gains 5 new action rows behind the
`canRedeploy` / `host` / `githubRepo` / `vercelProjectID` /
portal-folder guards, a confirmation `.alert` for the redeploy
flow, a bottom-pinned `ToastBanner` overlay, a system share sheet
binding for the client portal folder via a new
`ProjectPortalLocator` helper (scans `Documents/client-portals/` for
folders whose name starts with the project slug, sorts by
modification date desc). `RootView`'s HomeView gains
`portfolioKPIBar`, `loadPortfolioSnapshot()`,
`refreshAllHealth(origin:)`, `.task` + `.refreshable` modifiers,
and a new `PortfolioHealthSheet` view with a per-project status row
table reading from `ProjectHealthCache.shared`. `ProjectsView`'s
ProjectCard gains `deploymentState: String?` hydrated from
`ProjectHealthCache.shared.bundle(for:)` and a new
`deploymentPill(for:)` view that maps READY / BUILDING / QUEUED /
ERROR to color-coded capsule chrome. `NewProjectSheet` adds the
optional Vercel Project ID field. `SettingsView`'s
`testVercelConnection()` now pulls the first known
`vercelProjectID` from SwiftData and hits
`deployments(projectID:limit:)` for a real scoped check.

21 new FR/EN xcstrings keys under `project.action.*` /
`project.action.redeploy.*` / `home.kpi.builds.*` /
`home.refresh.pull` / `projects.refresh.pull` /
`portfolio.sheet.*` / `project.card.deploymentPill.*` /
`project.new.vercelProjectID` namespaces. 7 new MINDTelemetry
breadcrumbs (`vercel.redeploy.tapped/confirmed/success/failed`,
`portfolio.health.snapshot`, `portfolio.sheet.opened`,
`home.pulldown.refresh`, `projects.pulldown.refresh`, plus 4
per-action surface breadcrumbs `project.openSite/openRepo/openVercel/sharePortal.tapped`).

Tests: 6 new `PortfolioHealthAggregatorTests` (empty input zero
counts, 3 READY zero builds, 2 READY + 1 BUILDING one in progress,
ERROR within 24h counted, ERROR > 24h dropped, avg Lighthouse
performance mean), 6 new `VercelRedeployURLTests` (body carries
`name`, `gitSource.type == "github"`, `gitSource.repo` echoes
input, `target == "production"`, default `ref == "main"`, explicit
branch overrides default), 1 new test on `VercelClientTests`
locking the `/v13/deployments` URL shape. 824 tests total (was
811), 19 skipped, 0 failures. Build SUCCEEDED on iPhone 17 Pro
simulator. Vision verify at `mind/screenshots/v1.0-alpha.9.png`
shows the host launching clean on the Cockpit with the 4-cell KPI
bar visible immediately under the greeting subtitle: "4 leads · 5
actifs · 0 builds · 0 erreurs" (zero-data state — the cache hasn't
been populated yet on this fresh build, matching the acceptance
criteria).

Future ⏳ items unlocked by this wave: repository-aware audit
(audit le code source pas juste l'URL), Mac Catalyst polish +
Stage Manager, iOS 26 widgets refresh on the new Project + Vercel
surface, APNs Notification Service Extension for deploy-failed
push notifications.

## v1.0-alpha.8 (live integration wave) — Vercel + GitHub live integration in ProjectDetail ✅

**What**: Surface live deployment state, recent commits, repo stats,
and Lighthouse score per Project right inside `ProjectDetailSheet`.
New `ProjectHealthKit` module wraps the Vercel + GitHub + PageSpeed
APIs behind a soft-failing actor surface, a 5-minute in-memory +
on-disk cache (`ProjectHealthCache`), and two Keychain-backed token
stores (`VercelTokenStore` + `GitHubTokenStore`). Settings ships an
"Intégrations dev" section that mirrors the Notion / Linear sections
(paste token, save, "Test connexion" with green/red dot). The
cockpit fantasy lights up — tap any project, the sheet renders the
latest deployment chip (READY / BUILDING / ERROR / CANCELED /
QUEUED), the last commit SHA + message + author, a 4-cell
Lighthouse grid (Perf / A11y / Best / SEO), the repo stats (stars /
open issues / last push), and the 5 most recent commits.

Shipped 2026-05-20: new `ProjectHealthKit` module under
`mind/Modules/ProjectHealthKit/Sources/` — `VercelClient` actor
(`deployments(projectID:limit:)`, `latest(projectID:)`,
`health(projectID:)`, `validateToken()`, static
`deploymentsURL(...)` URL builder) backed by `VercelDeployment` +
`VercelHealth` Sendable Codable value types + `VercelClientError`
Equatable enum (`.noToken`, `.http(Int)`, `.decode`,
`.network(String)`) for soft-fail classification. `GitHubClient`
actor with `recentCommits(repo:limit:)`, `repoStats(repo:)`,
`openIssues(repo:limit:)`, `validateToken()`, plus the three static
URL builders (`commitsURL` / `repoURL` / `issuesURL`) exposed for
tests. Value types `GitHubCommit` / `GitHubRepoStats` / `GitHubIssue`
are all Codable + Identifiable so SwiftUI ForEach reads them
directly. `LighthouseProbe` actor wraps Google PageSpeed Insights
v5 (no API key required for personal use), exposing the 4-category
score + 3 Core Web Vitals via `LighthouseScore`. The static
`endpoint(forHost:strategy:)` helper prepends `https://` when the
project's `host` lacks a scheme and rejects empty hosts outright.
`ProjectHealthCache` actor mirrors the SEOSwarmStore / FollowUpStore
shape: per-project JSON under `Documents/project-health/<UUID>.json`,
in-memory cache backing every read, soft-fail telemetry on every
disk error (`projectHealth.cache.{mkdir,write,decode}.failed`),
5-min TTL with `isFresh(_:now:)` for the UI to gate spinner vs
cached render, and a `update(_:keyPath:value:)` partial-mutate
helper so the fan-out fetcher can land Vercel / GitHub /
Lighthouse independently. `VercelTokenStore` + `GitHubTokenStore`
use distinct Keychain service identifiers
(`app.mind.ios.{vercel,github}`, account `personal-token`)
mirroring `NotionTokenStore`.

`ProjectDetailSheet.swift` gains two sections between Aperçu and
Leads — `vercelSection` (state chip + last-deployment row + 4-cell
Lighthouse grid + "Voir sur Vercel" Link) and `githubSection`
(stars / open-issues / last-push stats row + 5 most-recent commits
+ "Voir sur GitHub" Link). Each section ships skeleton rows while
loading, a "token manquant — ouvre Réglages → Intégrations dev"
CTA when the Keychain returns nil, and a distinct empty state when
the project has no `vercelProjectID` / `githubRepo` configured. The
new `.task(id: project.id)` reads from `ProjectHealthCache.shared`
first (cache.hit / cache.miss telemetry), then fans out three
parallel fetches (Vercel `latest`, GitHub `recentCommits` +
`repoStats`, Lighthouse `score`) that each land on their own clock
and update their cache slot via `update(_:keyPath:value:)`.

`SettingsView.swift` gains an `integrationsDevSection` between the
Linear section and the Invoice section — two paste-PAT fields with
eye toggles, save + clear + "Test connexion" CTAs, green/red status
dots that reflect the last `validateToken()` call. Tokens hydrate
on appear via the existing onAppear block.

29 new FR/EN xcstrings keys under the `settings.integrations.*` /
`project.vercel.*` / `project.github.*` / `home.kpi.*` namespaces.
17 new MINDTelemetry breadcrumbs (`vercel.token.saved/validated/failed`,
`vercel.deployment.fetched/fetch.failed`,
`github.token.saved/validated/failed`,
`github.commits.fetched/fetch.failed`,
`lighthouse.probe.completed/failed`,
`projectHealth.cache.hit/miss/write/mkdir.failed/write.failed/decode.failed`).
Tests: 6 `VercelClientTests` (Codable round-trips for
`VercelDeployment` + `VercelHealth`, URL builder shape, error
Equatable), 7 `GitHubClientTests` (Codable + Identifiable
round-trips, the three URL builders, empty-repo nil guard, error
Equatable), 4 `LighthouseProbeTests` (Codable round-trip,
`overall` average formula, endpoint builder scheme + mobile-default,
empty-host rejection), 5 `ProjectHealthCacheTests` (save+load
round-trip, TTL fresh/stale boundary, unknown-project nil,
partial-update preserves slots, clearAll wipes + survives fresh
instance), 4 `IntegrationTokenStoresTests` (Vercel + GitHub
Keychain round-trip + clear, skip-on-Simulator guarded by
`#if targetEnvironment(simulator)`). 811 tests total (was 755 in
v0.22.1), 19 skipped, 0 failures. Build SUCCEEDED on iPhone 17 Pro
simulator. Vision verify at `mind/screenshots/v1.0-alpha.8.png`
(host launches clean on the Cockpit — Vercel + GitHub surfaces are
intentionally hidden behind the ProjectDetail tap, matching the
host-launches-clean vision bar used by v0.22.1 / v0.31.1 /
v1.0-alpha.7).

Future ⏳ items unlocked by this wave: APNs Notification Service
Extension for deploy-failed push notifications, Reaper dead-code
sweep across the Cockpit Studio pivot, repository-aware audit
(audit le code source pas juste l'URL), Mac Catalyst polish +
Stage Manager layout pass, iOS 26 widgets refresh on the new
Project + Vercel surface.

## v1.0-alpha.2 — Project + Lead + Deliverable data spine ✅

Shipped 2026-05-20: introduces `Project`, `Lead`, `Deliverable` as
SwiftData `@Model` classes in `GraphCore`, sharing the same CloudKit-
compatibility constraint set as `Node` (inline defaults, optional
relationships with nil defaults, `@Attribute(.unique)` on UUID).
`GraphContainer.schema` registers the three new types alongside the
legacy Node / Edge / FocusSessionRecord rows — the pivot stays
additive at the data layer because the CloudKit daemon refuses to
drop existing schemas. `SpotlightIndexer` gains
`index(_ project: Project)`, `index(_ lead: Lead)`, and
`index(_ deliverable: Deliverable)` plus prefixed unique identifiers
(`project:<uuid>`, `lead:<uuid>`, `deliverable:<uuid>`) so deep-link
dispatchers can route purely from the string prefix.
`LeadWebhookPayload` locks the on-the-wire contract a future
Cloudflare Worker (alpha.5) will use to POST inbound leads to MIND —
HMAC-SHA256 sign/verify helpers (CryptoKit) ship now so the iOS side
is ready even though the worker isn't. `Project.seedDemoProjects(in:)`
idempotently inserts the 5 real Numelite projects (AZ Construction,
AZ Epoxy, AZ Concept, IEF & Co, Sconnect) on first launch, gated on
`mind.demo.seeded` UserDefaults flag. New telemetry breadcrumb
`project.demo.seeded` with `count` payload. 4 new test files (38
tests total) lock the model defaults, enum accessor round-trips, slug
normalisation, MRR aggregation, HMAC sign/verify happy path + every
documented failure mode (wrong secret, tampered payload, empty / wrong-
length signature, case-insensitive accept).

### v1.0-alpha.3 — HomeView "Aujourd'hui" lead inbox ✅
**What**: Rewrite HomeView to surface the `@Query var leads: [Lead]`
sorted `receivedAt` descending, replacing the greeting-only layout
from alpha.1. New `LeadRowCard` (LiquidCard tokens), tap → detail
sheet with status pill + Claude-drafted reply editor. **Acceptance**:
unanswered leads from today float to the top, status chip lets Mehdi
mark `.contacted` / `.qualified` / `.spam` from the row swipe action.
Shipped 2026-05-20: rewrote `HomeView` top-to-bottom around the
`@Query<Lead>` filtered by `status == "new"`, sorted through the new
pure `LeadInboxSorter.sort(_:by:)` projection (lives in GraphCore so
tests + ProjectDetailSheet share the same code path). HomeView now
opens with greeting "Bonjour Mehdi 👋" + a live subtitle
("X leads · Y projets actifs · Z€/mois" — bound to
`ProjectMRR.total(of:)` + `ProjectMRR.activeCount(in:)` which sum only
active retainers per the documented FR locale convention). Below it
ride three new cards: Boîte leads (top-10 new leads, avatar circles
tinted to each parent Project's `primaryColor`, name + project chip +
2-line preview + relative time, swipe → Répondre, context menu →
Qualifié / Spam, tap → LeadDetailSheet); Projets actifs (horizontal
scroll-snap of 200×130 mini-cards, MRR/Forfait pill in the project
accent color, stack chip, tap → ProjectDetailSheet); the legacy
Pipeline summary + Audit card stack stayed. New
`LeadDetailSheet.swift` carries the avatar header, contact name,
project chip, form-type pill, status pill with relative timestamp,
selectable original message, editable draft reply with a "Générer
brouillon" CTA that fires `OutreachEmailGenerator.shared.generate(...,
variantCount: 1)` and writes the first variant straight back into
`lead.draftReply` via `@Bindable`. Action stack covers Qualifié /
Gagné (opens InvoiceSheet pre-seeded with `clientNodeID: lead.id` +
contact name/email) / Perdu (alert prompts for a one-shot reason
persisted on `lead.statusReason`) / Spam — every transition saves
via `try? context.save()`, touches the parent Project's
`lastActivityAt`, and emits `lead.status.changed` with from→to
breadcrumb. Metadata disclosure surfaces sourceURL, receivedAt,
formType, userAgent, IP hash. New `LeadDemoSeed.swift` extension
idempotently injects 4 demo leads (Sarah Bensalem + Marc Petitjean +
Pierre Loison → AZ Construction, Lucie Aubry → IEF & Co) on first
launch behind the `mind.demoLeads.seeded` flag — vision verify shows
the HomeView card stack lands populated. 8 new
`LeadInboxSortingTests` lock date-desc, status priority (`.new` →
`.qualified` → `.contacted` → `.won` → `.lost` → `.spam`), tie-
break by date inside a bucket, empty + single + determinism. Plus
~25 FR/EN xcstrings keys (`home.aujourdhui.title`,
`home.leads.empty.{title,detail}`, `home.greeting.subtitle.format`,
`lead.action.{respond,qualified,won,lost,spam}`,
`lead.detail.{message,draftReply,generateDraft,metadata}`,
`lead.status.*`, `lead.formType.*`, `lead.metadata.*`,
`lead.action.lost.{reasonTitle,reasonPlaceholder,confirm}`) +
2 telemetry breadcrumbs (`home.leads.opened`, `lead.detail.opened`,
`lead.status.changed`, `lead.demo.seeded`). 619 tests total
(was 553), 12 skipped, 0 failures.

### v1.0-alpha.4 — ProjectsView replaces ClientsView ✅
**What**: Replace the legacy `ClientsView` with `ProjectsView`
backed by `@Query var projects: [Project]`. Columns: name + host,
stack chip (`nextjs` / `wordpress` / …), MRR (formatted EUR), last-
activity relative date. Sort: `lastActivityAt` desc. Add detail
sheet showing per-Project leads + deliverables. **Acceptance**:
seeded portfolio renders 5 rows, MRR total card sums retainer rows
correctly, tap → detail sheet shows AZ Construction's leads.
Shipped 2026-05-20: new `ProjectsView.swift` swap into the `.clients`
tab via `RootView.content` — legacy `ClientsView` stays compiled for
the cron-resurrection edge case but no longer owns the tab. Header
(title + count + "+" CTA opening `NewProjectSheet`), search field
(case-insensitive substring match against name + host through pure
`ProjectSorter.filter(_:query:)`), 3-key segmented control
(Activité / MRR / A-Z, default `.activityDescending`) that posts
`project.list.sortChanged` with the rawValue, then a LazyVStack of
88pt `ProjectCard`s: 48pt avatar circle with the first letter on a
`Project.primaryColor`-tinted background, name + monospaced host,
stack badge + lifecycle dot row (green active / orange maintenance /
sky discovery / gray archived), right-aligned MRR pill (`€X/mo` for
retainer, `Forfait X€` for oneshot). Tap → `ProjectDetailSheet.swift`:
header with avatar + name + host + MRR pill + stack/contract pills,
Aperçu (host link, GitHub repo link `https://github.com/{repo}`,
last-activity relative date), Leads récents (top-5 via
`LeadInboxSorter.sort(_:by: .dateDescending)`, tap → LeadDetailSheet,
empty-state copy), Livrables (kind-iconed deliverable rows: page →
doc.text, screenshot → photo, audit → speedometer, invoice → doc.
richtext, asset → shippingbox), Actions (Lancer un audit pre-seeds
AuditSheet with `https://{host}`; Voir tous les leads opens
`ProjectLeadsListSheet` with a date/status sort picker; Archiver
fires a confirm alert that sets `lifecycleStageEnum = .archived` +
`touchActivity()`), Notes section is a markdown TextEditor bound via
@Bindable that persists into `project.notes` on every keystroke.
`NewProjectSheet` is a 3-section Form (Identity: name + host + repo,
Stack picker spanning every `ProjectStack`, Revenue: contract type
picker + amount field — switches between MRR EUR and forfait EUR per
contract) that on save inserts the Project and emits
`project.new.created`. New pure helpers — `ProjectSorter` (8 tests:
activity desc, MRR desc, alphabetical FR locale-aware,
archived bottom-pin, internal-bucket sort, empty + single,
filter() name + host case-insensitive) + `ProjectMRR` (5 tests:
total sums active retainers only, empty = 0, single retainer,
`formatEUR(_:)` shape, active counts split retainer from total).
8 new telemetry breadcrumbs: `project.list.sortChanged`,
`project.detail.opened`, `project.new.created`. Plus ~30 FR/EN
xcstrings keys (`project.list.*`, `project.detail.*`,
`project.action.*`, `project.new.*`, `project.contract.*`).

### v1.0-alpha.5 — Cloudflare Worker template + `@mind/lead-webhook` SDK ✅
**What**: Ship a Cloudflare Worker template under
`mind/tools/lead-webhook-worker/` that any deployed Numelite site
can drop into `workers/lead-webhook.ts`. Companion npm package
`@mind/lead-webhook` exposes `signAndPost(payload, secret, endpoint)`.
Per-project provisioning generates a `webhookSecret` on the Project
and surfaces it as a copy-paste env var in ProjectDetailView.
**Acceptance**: a POST to MIND's ingest endpoint with the worker-
signed payload lands as a `.new` Lead within 2s; tampered payloads
or wrong secrets are rejected with HMAC verification breadcrumbs.
Shipped 2026-05-20: new `mind/tools/cloudflare-worker/` Worker template (POST `/v1/leads` with HMAC-SHA256 `X-MIND-Signature` verify via Web Crypto API, KV `LEADS` put keyed `lead:<projectID>:<ts>:<uuid>` with 30-day TTL, GET `/v1/leads?since=<iso>` pull-fallback capped at 100, OPTIONS 204 CORS preflight, ES256 APNs JWT mint + best-effort push with `app.mind.ios` topic, four required secrets `WEBHOOK_SECRET`/`APNS_KEY_P8`/`APNS_KEY_ID`/`APNS_TEAM_ID`/`APNS_DEVICE_TOKEN`); 16 Vitest cases on routing + HMAC (`tests/index.test.ts` with in-memory FakeKV stub, `timingSafeEqual` unit tests, valid-signature → 200, wrong-secret → 401, missing-header → 401, empty body → 400, missing required field → 400, unknown `formType` → 400, malformed email → 400, non-JSON body → 400, configurable TTL plumbed end-to-end, GET empty → 200, GET capped, GET `since=` filter via key-timestamp parsing, GET unparseable `since` → 400, OPTIONS 204 + CORS headers, 404 + 405 routing). New `mind/tools/npm-sdk/` shipping `@mind/lead-webhook@0.1.0` (typed `LeadPayload` with `LeadFormType` union, `SendLeadOptions`, typed `MINDWebhookError` with seven discriminated `code` cases, pure `sign(payloadJSON, secret) → hex` mirroring iOS `LeadWebhookPayload.sign(...)` byte-for-byte, `canonicalEncode(...)` sorted-keys encoder mirroring iOS `canonicalEncoder`, `sendLeadToMIND(payload, options)` injecting `receivedAt: new Date().toISOString()`, AbortController 5s timeout, normalising trailing slashes, mapping every status to the matching `MINDWebhookError.code`); 14 Vitest cases (`tests/sign.test.ts` × 5 + `tests/index.test.ts` × 9 covering RFC 4231 reference vector parity, deterministic signing, success path with intercepted fetch, every error code path, validation short-circuits, URL slash normalisation, ISO `receivedAt` injection, canonical encoder property tests). 5-step `mind/tools/INSTALL_LEAD_WEBHOOK.md` guide with Mermaid flow diagram (deploy Worker → generate `openssl rand -hex 32` secret → upload APNs `.p8` + Key ID + Team ID → paste device token → `npm install @mind/lead-webhook` + 6-line Next.js route example). iOS slice: new `WebhookSecretStore.swift` (Keychain wrapper, service `app.mind.ios.webhook`, same shape as APIKey/Notion/Linear stores); `SettingsView.swift` "Lead Webhook" section above the iCloud card (Liquid Glass capsule secret field with eye toggle + Save/Saved/Clear pattern matching every other token section, divider, per-Project copy-row list with iris-tinted `doc.on.doc.fill` icon + monospace UUID + clipboard glyph, empty-state hint when no Projects exist yet, success haptic + `webhook.secret.saved`/`webhook.projectID.copied`/`webhook.secret.cleared` telemetry breadcrumbs, toast alert after copy with "Paste %@'s UUID into MIND_PROJECT_ID" body); 6 new FR/EN xcstrings keys (`settings.webhook.{section,subtitle,projects.label,projects.empty,copied.title,copied.body}` with `%@` placeholder preserved across translations). Tests: 4 `WebhookSecretStoreTests` (read-when-never-saved → nil, clear-on-empty idempotent, save/read round-trip + overwrite + clear gated behind `XCTSkipIf(simulator)` for the keychain-signing-identity caveat); `LocalizationTests` extended with `test_webhookStrings_resolveBothLanguages` (8 asserts including `%@` survival check). Total iOS test files += 1, plus the Worker + SDK test suites in their own subfolders run via `npm test`.

### v1.0-alpha.6 — Bootstrap scaffolder (new project wizard) ✅
**What**: "Nouveau projet" CTA from ProjectsView → multi-step
wizard: name + slug, stack, contract type, MRR / one-shot, host,
GitHub repo, Vercel project ID, paste webhook secret (or
generate one). Wizard concludes by minting the Project row + a
GitHub-template-style README under `mind/tools/scaffolds/<stack>/`.
**Acceptance**: a fresh project is wizardable end-to-end in
under 60 seconds, shows up on the Cockpit immediately.
Shipped 2026-05-20: Bootstrap Scaffolder ships a 3-step wizard
(Identity / Stack / Modules) producing a runnable Next.js scaffold
script + ZIP, pre-wired to `@mind/lead-webhook`. New `BootstrapKit`
module wraps three pure surfaces — `BootstrapBlueprint` (Sendable
+ Equatable + Codable value type captured by the wizard);
`BootstrapScriptGenerator.bashScript(for:)` (idempotent
`set -e -u -o pipefail` bash with `gh repo create`, heredocs for
every template file, `git push -u origin main`, `vercel link
--project=<slug>` with soft-fail fallbacks); `BootstrapZipBuilder
.archive(for:)` (in-memory `[String: Data]` mirror of the same file
set the script heredocs); plus `TemplateLibrary` (Next.js 15 +
Tailwind 4 + Resend + Zod + `vercel.json` security headers +
`.env.example` listing every env var). Contact route handler
forwards every form submission through `sendLeadToMIND(...)` before
firing Resend so the cockpit captures the lead even when email
errors. Optional bundle toggles (admin backoffice with bcrypt+jose
auth, blog MDX with `next-mdx-remote`, i18n FR/EN with `next-intl`,
Stripe with `stripe.config.ts` + webhook handler) gate their own
heredocs + archive entries — verified by 4 `*_ONLY_when…` tests.
iOS UI ships `BootstrapWizardSheet` (3-step `TabView` with progress
dots, Liquid Glass cards, 5 preset color chips + hex input,
disabled-until-valid bottom CTA) + `BootstrapResultSheet`
(checkmark hero, 4 actions — Copier le script /
Partager le script via tmp `.sh` + UIActivityVC / Partager le ZIP
via `NSFileCoordinator` `.forUploading` zip / Voir le projet → routes
back to .clients tab). HomeView gets a "Bootstrap projet" Liquid
card with `sparkles.rectangle.stack.fill` icon between Pipeline and
the audit stack. ProjectsView "+" CTA replaces the basic
`NewProjectSheet` with the wizard. 29 new Localizable.xcstrings
keys FR/EN. 6 new MINDTelemetry breadcrumbs
(`bootstrap.wizard.opened` / `bootstrap.blueprint.created` /
`bootstrap.project.created` / `bootstrap.script.copied` /
`bootstrap.script.shared` / `bootstrap.zip.shared`). 32 new pure
tests across 4 files (BootstrapBlueprintTests × 6,
BootstrapScriptGeneratorTests × 14, TemplateLibraryTests × 8,
BootstrapZipBuilderTests × 4) — 684 tests total (was 652), 15
skipped, 0 failures. Vision verify saved at
`mind/screenshots/v1.0-alpha.6.png` (HomeView launches clean, lead
inbox + projects carousel populated) plus
`mind/screenshots/v1.0-alpha.6-example.sh` (sample wizard output
for AZ Construction with admin + i18n toggled on).

### v1.0-alpha.7 — SEO Swarm Orchestrator ✅
**What**: Mehdi's batch `{service}×{zone}` pattern as a first-
class feature. New `SEOSwarmSheet`: list every service + every
zone, generate the matrix preview, ship each page as a
`Deliverable(kind: .page)` attached to the Project. Hook into the
existing AuditKit pipeline so each generated page gets a lighthouse
score on commit. **Acceptance**: AZ Construction's 8 services × 12
Paris zones → 96 deliverables generated in one batch, each with
its own row on the Cockpit feed.
### v1.0-alpha.8 — Project Health Pulse (pure substrate) ✅

**What**: Persistent per-Project HTTP health probe results — pure
value types + pure classifier + on-disk store ready for a future
background probe wave. Surfaces immediately as a tiny status dot on
each ProjectCard's avatar (top-right corner) and a "Santé du site"
row inside ProjectDetailSheet's overview section. The dot maps
`(statusCode, responseTimeMs)` → `HealthStatus` (online / degraded /
error / offline / unknown), colour-coded green / orange / red /
red / hidden. The actual URLSession probe lands in v1.0-alpha.9 —
this version ships the substrate behind it so the SwiftUI surface,
the persistence layer, and the classifier are already locked when
the probe layer lights up. **Acceptance**: `HealthPulseStore`
round-trips one pulse per project under
`Documents/health-pulses/<projectID>.json`; pulse hydration survives
a fresh `HealthPulseStore` instance over the same root URL; pure
`HealthClassifier.classify(...)` maps every documented bucket
deterministically (2xx fast → online, 2xx slow → degraded, 3xx →
degraded, 4xx/5xx → error, transport sentinel → offline); ProjectCard
status dot renders coloured only when a pulse exists; ProjectDetailSheet
"Site health" row hides cleanly when the pulse status is `.unknown`.

Shipped 2026-05-20: new `HealthPulse` Sendable Codable value type +
`HealthStatus` enum (5 buckets, `severityRank` for "most-critical-
first" sort) + `HealthClassifier` pure mapper (`classify(statusCode:
responseTimeMs:degradedThresholdMs:)` with the 1500 ms default
threshold matching the v0.4 audit "performance" probe's slow cutoff)
+ `HealthPulseHelpers` (sortByCriticalFirst + formatRelativeAge
through `RelativeDateTimeFormatter`) all in GraphCore so no new Tuist
module is needed. `HealthPulseStore` actor mirrors the
`SEOSwarmStore` / `FollowUpStore` shape: per-file `<projectID>.json`
under `Documents/health-pulses/`, in-memory cache backing every
read, soft-fail telemetry on every disk error
(`health.store.{hydrate,decode,mkdir,write}.failed`), atomic writes,
hydration on first read across instances. ProjectsView's
`ProjectCard` gains a `.task(id: project.id)` that loads the latest
pulse and renders a 12pt colour dot on the avatar's top-right corner
when status != `.unknown` (a `.background` stroke makes it pop on
both light and dark Liquid Glass cards). ProjectDetailSheet's
overview section gains a `healthRow(pulse:)` rendering the status
label + relative age + response-time pill behind the same
`.unknown` gate. 6 new FR/EN xcstrings keys
(`project.detail.health`, `health.status.{online,degraded,error,
offline,unknown}`). Tests: 16 new `HealthClassifierTests` cover
every status-code boundary (fast 2xx → online, 299 still online,
slow 2xx → degraded, threshold-`==` is degraded, just-under-threshold
stays online, 301/302 redirect → degraded, custom threshold override,
404 → error, 500 → error, 503 → error, transport sentinel → offline,
negative non-sentinel → offline, 100-199 → offline, severity rank
ordering invariant, sortByCriticalFirst groups+date-desc inside
bucket, empty input → empty output, Codable round-trip preserves
every field). 7 new `HealthPulseStoreTests` cover the on-disk
contract (save→load round-trip, save-replaces-previous for same
projectID, missing-project → nil, allPulses surfaces every record,
delete removes from cache + disk, clearAll wipes + idempotent,
hydration repopulates cache across fresh instance over same root).
`LocalizationTests` extended with `test_healthPulseStrings_resolveBothLanguages`
(12 asserts FR + EN). Sample reference data at
`mind/screenshots/v1.0-alpha.8-sample-pulses.json` documents the
five status-bucket cases against the real Numelite project hosts.
708 tests total, 15 skipped, 0 failures (was 684 in v1.0-alpha.6).
Vision verify at `mind/screenshots/v1.0-alpha.8.png` (host launches
clean on the Cockpit — the dot + Site health row are intentionally
hidden because no pulse has been saved yet on a fresh simulator,
which is the documented `.unknown` soft-default).

Shipped 2026-05-20: SEO Swarm Orchestrator — 3-step wizard generating N {service}×{zone} Next.js pages via Claude, exports as ZIP for `cp -r` into the client repo. New `SwarmKit` module ships five pure surfaces: `SEOSwarmJob` / `SwarmZone` / `SwarmPage` / `SwarmJobStatus` Sendable Codable value types; `SEOSwarmPromptBuilder.systemPrompt()` + `pagePrompt(project:service:zone:)` (FR senior SEO copywriter persona, 1500-2500 word page brief grounded on zone display name + department code + optional population, JSON-only response contract with `{title, metaDescription, h1, bodyMarkdown, jsonLD}` schema, no-hallucination guardrail when population nil); `SEOSwarmOrchestrator` actor (3 in-flight pages via TaskGroup with soft-fail per page, `AsyncStream<ProgressEvent>` for live UI updates, `.started/.pageCompleted/.pageFailed/.completed/.cancelled` event kinds, status reconciliation into `.completed`/`.partial`/`.failed`); `SEOSwarmStore` actor (per-job JSON persistence under `Documents/seo-swarm-jobs/<id>.json` with in-memory cache + soft-fail telemetry mirroring `FollowUpStore`); `SEOSwarmExporter.nextJSAppRouter(pages:)` (one `src/app/<service>/<zone>/page.tsx` per page with Next.js Metadata + JSON-LD script tag + ReactMarkdown body); `SwarmZoneCatalog` (226 IDF + regional commune zones with INSEE population data, URL-safe slugs, alphabetically sorted, filter helper for autocomplete). iOS UI ships `SwarmWizardSheet` (3-step wizard: Cible → chips picker for project/services/zones with autocomplete against SwarmZoneCatalog, Configuration → matrix preview + EUR cost estimate based on Sonnet 4.6 pricing × 0.93 EUR/USD with methodology alert, Lancement → confirm dialog + primary CTA, running view with progress ring + counter + scroll log + cancel CTA, completed sheet with 3 actions Voir résumé/Exporter ZIP/Pousser GitHub). HomeView gains a `tornado`-iconed aqua "SEO Swarm" card after the audit card stack; ProjectDetailSheet gains a "Lancer un swarm SEO" action row that opens the wizard pre-selected on the project. 7 MINDTelemetry breadcrumbs (`swarm.wizard.opened`, `swarm.job.created`, `swarm.job.started`, `swarm.page.generated`, `swarm.page.failed`, `swarm.job.completed`, `swarm.zip.exported`). 19 new FR/EN xcstrings keys under `swarm.*` + `home.swarm.*` namespaces. Tests: 11 `SEOSwarmPromptBuilderTests` (FR mention, project + service + zone anchors, JSON-only contract, LocalBusiness mention, word count range, determinism, slot variance, empty service fallback, population gracing); 6 `SEOSwarmExporterTests` (one file per page, forward-slash paths, route + JSON-LD + markdown body presence, determinism); 5 `SwarmZoneCatalogTests` (>=200 zones, non-empty fields, no duplicate slugs, URL-safe slugs, alphabetical sort); 4 `SEOSwarmStoreTests` (save+load round-trip, list all, delete, load-missing nil). `LocalizationTests` extended with `test_swarmStrings_resolveBothLanguages` (19 FR + EN asserts including format-string placeholder survival). Vision verify at `mind/screenshots/v1.0-alpha.7.png` (host launches clean on the Cockpit) with `mind/screenshots/v1.0-alpha.7-example.txt` carrying a sample generated SwarmPage JSON for AZ Construction × Verrière × Puteaux (92) so Mehdi sees the quality bar.

## v1.0-alpha.1 — Radical cleanup (Cockpit Studio pivot) ✅

Shipped 2026-05-20: gut the second-brain modules + UI surfaces that
no longer serve the studio-cockpit pivot. NodeKind narrowed to
`.client` / `.audit` (+ `.project` / `.lead` placeholders for Wave B).
RootView reduced from 3056 → ~786 lines (4 tabs: Home, Clients,
Pipeline, Settings). OnboardingView rewritten to Cockpit Numelite
copy. MINDApp.swift stripped of every share-extension, reminders,
daily-brief, meeting-brief lifecycle call. Project.swift dropped the
Widget + ShareExtension targets; Module.swift dropped 7 module cases.

Long-form roadmap for the next 50 versions of MIND. Each version is
a coherent, single-PR-shippable unit with concrete acceptance
criteria. Engineered as the input for the autonomous iteration agent
defined in `.claude/agents/mind-iterator.md`.

Versions are tagged ⏳ (pending), 🟡 (in progress), ✅ (done). The
iteration agent picks the lowest-numbered ⏳ version every run.

---

## North-star vision

MIND is the second-brain Mehdi (and later, every freelance designer /
PM / consultant) carries everywhere — iPhone, iPad, Watch, Mac,
Vision Pro — to capture, structure, audit, and recall every business
prospect, client, idea, note, and focus session. The Universal Object
Graph means notes today, clients tomorrow, audits the day after — all
queryable from the same place.

The app feels like Apple-designed it: Liquid Glass, native paces,
zero friction. The intelligence layer is invisible until the user
needs it (auto-tagging, summarize, audit synthesis, recall via
semantic search). The cloud reasoning (Claude / GPT Image 2) is opt-in
per feature, never gated behind sign-up.

---

## Chapter 1 — Submission & first cohort (v0.2 → v0.10)

The first cohort = Mehdi + 5 hand-picked friends running iPhone 15
Pro or newer on iOS 26+. Goal of this chapter: hit "comfortably
usable solo" on TestFlight.

### v0.2 — Background fetch + AuditController tests ✅
**What**: BackgroundTasks framework registration so the app can wake
periodically (every ~6h) and pull CloudKit changes silently. New
`AuditControllerTests` cover happy path / cancellation / failure for
the phase state machine. **Acceptance**: BGAppRefreshTask registered,
6 new tests pass, audit phase state diagram covered.
Shipped 2026-05-19: BGAppRefreshTask `app.mind.ios.refresh` registered in MINDApp.init via BackgroundRefreshScheduler (GraphCore), scheduled on scenePhase=.background, 6 AuditController state-machine tests added (101 total, 0 failures).

### v0.3 — Share Extension iOS ✅
**What**: New `MINDShareExtension` Tuist target with
SLComposeServiceViewController. User shares any URL or text from
Safari/Mail/Notes/Messages → MIND captures it as a node with
`source = clipboardURL` and auto-creates a `client` if the URL has a
known SaaS host. **Acceptance**: extension shows up in share sheet,
URL capture creates correct node, screenshot of share flow saved.
Shipped 2026-05-19: MINDShareExtension appExtension target wired via Tuist, SLComposeServiceViewController serialises URL+text shares into a cross-process `ShareInbox` queue (App Group group.app.mind.ios), host MIND app drains the queue on .active scenePhase and auto-creates a `client` Node when the URL host is a known SaaS (Stripe/Notion/Linear/GitHub/Figma/Vercel/Netlify/Shopify/Slack/Airtable/Anthropic/OpenAI/Apple/Google/Cloudflare). 14 ShareInboxTests added (115 total, 0 failures).

### v0.4 — Per-probe error UI + retry ✅
**What**: AuditSheet's error path today shows a global message. Refactor
AuditController to surface per-probe errors (`Dictionary<ProbeKind,
Error>`) and the running view shows each probe with green/red dot.
"Retry failed probes" CTA. **Acceptance**: 5 simulated probe failures
show 5 distinct error rows, retry only re-runs failed ones.
Shipped 2026-05-19: ProbeKind/ProbeState added on AuditController, per-probe rows + retry CTA in AuditSheet, 8 new tests (124 total).

### v0.5 — Markdown editor for Notes ✅
**What**: Replace TextEditor in NodeDetailView with a markdown editor
(syntax highlight + on-blur render). Use AttributedString with
NSAttributedString.MarkdownParsingOptions for rendering, plain text
for editing. **Acceptance**: `**bold**`, `# heading`, `- list`,
`[link](url)` all render correctly on blur, edit on tap.
Shipped 2026-05-19: NodeDetailView's default (non-audit, non-client) body now hosts a `MarkdownEditorCard` — tap the rendered MarkdownView to swap in a monospaced TextEditor bound to `node.content`, blur (tap outside or the "Aperçu" button) commits via `node.refreshEmbedding()` + `try? context.save()` + `SpotlightIndexer.index(node)` + a `node.edit` MINDTelemetry breadcrumb. Pure `MarkdownRenderer.attributedString(from:)` helper extracted in DesignSystem (uses `.full` parsing options so headings, lists, and links surface as distinct runs with `.link` URL attribute) and exercised by 7 new MarkdownRenderingTests covering bold, italic, level-1 + level-2 headings, monotonic heading point sizes, bullet list item presentation intent, and link URL extraction. MINDTests target now also links DesignSystem so the helper is reachable from the test bundle. 131 tests, 0 failures.

### v0.6 — Dynamic Type complete pass ✅
**What**: Every text in the app uses `.font(.system(.X, design:
.rounded))` with named text styles instead of hardcoded sizes. Test
on AX5 (largest) — no clipping, no overlap. **Acceptance**: full app
walkthrough at AX5 with screenshot per screen, no truncations.
Shipped 2026-05-19: every `.font(.system(size: N))` callsite in `RootView`, `AuditSheet`, `ClientsView`, `OnboardingView`, `SettingsView`, `NodeDetailView`, `LiquidButton`, and `LiquidPill` swapped to a named text style (`.headline`, `.subheadline`, `.body`, `.callout`, `.footnote`, `.caption`, `.caption2`, `.title3`) while preserving `design: .rounded` + `weight:`. Six intentional display-only sizes survive with documenting comments: the 64pt Deep Focus countdown timer (×2 — running + idle state), the 44pt audit hero score, the 40pt empty-state illustration glyphs in ClientsView (×2), and the 42pt / 32pt / 38pt onboarding icons centered inside their 96pt / 80pt circles. Greeting / card headlines / button labels now carry `minimumScaleFactor(0.7–0.9)` + appropriate `lineLimit(1–4)` so AX5 wraps cleanly inside its container. New `DynamicTypeAuditTests.swift` adds 7 structural locks (LiquidButton + LiquidPill init contracts, `Font.TextStyle` distinctness, AX5 still present in the `DynamicTypeSize` ladder, accessibility ladder monotonicity). AX5 + normal-size screenshots saved to `mind/screenshots/v0.6-ax5.png` and `mind/screenshots/v0.6.png`. 138 tests, 0 failures.

### v0.7 — i18n FR / EN complete ✅
**What**: Extract every visible string into `Localizable.strings`
with FR + EN catalogues. Default to FR for Mehdi, EN for the public
beta. Use SwiftUI's `String(localized:)` API. **Acceptance**: app
language switches with iOS Settings, every screen translates cleanly,
no string crashes.

Shipped 2026-05-19: `mind/App/Resources/Localizable.xcstrings` ships 121 keys
covering the visible first-launch path — Onboarding (4 pages), HomeView (greeting +
audit/Ask MIND/tasks/focus-week/life-modules cards + empty state + stats + recent),
AuditSheet (header / form / running / error / phase-step / probe-state accessibility),
ClientsView (header / subtitle including %lld plural / search / empty + no-results),
Settings (header + 6 section titles + save/saved/clear buttons + iCloud + danger
zone), QuickCaptureSheet (title / capture button / saving / clipboard banner / voice
accessibility). App-target files use `Text("key")` LocalizedStringKey lookup; module
files (Settings, Capture) explicitly pass `bundle: .main` so they resolve against the
app catalog rather than their own framework bundle. Time-based greeting/subtitle and
plural client subtitles use `String(localized:)`. Catalog written as JSON
String Catalog format (.xcstrings), JSON-validated. New `LocalizationTests.swift`
adds 7 tests that load the host app bundle's en.lproj / fr.lproj at runtime, verify
both .lproj directories ship, and assert anchor keys (`home.empty.title`,
`onboarding.start`, `audit.phase.*`, `settings.header.title`, `capture.title`,
`greeting.morning`) resolve to their expected FR and EN values. 145 tests, 0
failures (was 138 in v0.6). FR + EN screenshots saved to
`mind/screenshots/v0.7-fr.png` and `mind/screenshots/v0.7-en.png` — both show the
onboarding welcome page translating cleanly with no raw key leaks. Partial scope:
the audit-report sub-sections (Synthèse / Quick wins / Paris stratégiques / Risques
cachés / Détails techniques / Pitch / Export sheet / Brief preview) and the Notes /
NodeDetail / Chat / FocusHistory / Habits / Journal / Goals / Tasks views remain
on their original strings — they're not on the first-launch path and translate as a
follow-up v0.7.1 patch.

### v0.8 — Calendar (EventKit) integration ✅
**What**: Read events from the user's primary calendar, surface
upcoming meetings on HomeView in a new "Aujourd'hui" card. Tap an
event → create a `meeting` Node with date/participants pre-filled.
**Acceptance**: events render with name + time + location, tap creates
node, permission flow handled gracefully.
Shipped 2026-05-19: new `CalendarKit` module wraps EKEventStore via an
actor that soft-fails to `[]` when permission is denied; pure
`CalendarEvent` value type with `sortedByStart()` / `deduplicatedByID()`
helpers is reused by the new HomeView "Aujourd'hui" card. Card lists up
to 3 events with locale-formatted time + title + location, taps create a
`.meeting` Node (new NodeKind case) with attendees → tags and route into
`NodeDetailView`. `NSCalendarsFullAccessUsageDescription` +
`NSCalendarsUsageDescription` added in `Project.swift` with FR copy.
PrivacyInfo.xcprivacy untouched — EventKit has no Required Reason API
entry and calendar metadata stays in the user's CloudKit zone, so no
new collected-data declaration. 8 new tests in
`Tests/Sources/CalendarReaderTests.swift` cover init/defaults, sorting,
deduplication, locale-aware time formatting, and the
permission-denied soft-fail of `todayEvents()`. 153 tests, 0 failures
(was 145 in v0.7). Screenshot at `mind/screenshots/v0.8.png` shows the
calendar permission prompt firing on first launch with the exact French
copy, validating both the EventKit request path and the Info.plist
string.

### v0.9 — HealthKit weekly insights ✅
**What**: New module HealthKit. Pulls last 7 days of sleep, steps,
active minutes. Surfaces on HomeView in "Cette semaine" card under
Focus stats. **Acceptance**: weekly summary card shows values, permission
flow handled, opt-in via Settings.
Shipped 2026-05-19: new `HealthInsights` module wraps `HKHealthStore` via
an actor that soft-fails to `WeeklySummary.empty` when permission is
denied / HealthKit unavailable; pure `WeeklySummary` value type with
`.empty` / `isMeaningful` helpers gates a new HomeView "Cette semaine"
card (3 columns — steps, sleep avg, active minutes). Strict opt-in: a
new toggle in Settings → Préférences flips `healthInsightsEnabled` (FR
default `false`) and triggers `HealthReader.requestAccess()` only on
toggle-on. `NSHealthShareUsageDescription` +
`NSHealthUpdateUsageDescription` added in `Project.swift` with FR copy,
`com.apple.developer.healthkit` entitlement enabled, and
`NSPrivacyCollectedDataTypeHealth` entry declared in
`PrivacyInfo.xcprivacy` (not linked, not tracking, AppFunctionality
purpose) so App Store review passes cleanly. 6 new tests in
`Tests/Sources/HealthReaderTests.swift` cover init, `.empty`,
`isMeaningful`, and Equatable. 159 tests, 0 failures (was 153 in v0.8).
Screenshot at `mind/screenshots/v0.9.png` shows the host app launching
clean — the card is intentionally hidden because the Simulator
HealthKit is empty + opt-in is off, which is exactly the documented
soft-fail contract.

### v0.10 — Reminders bidirectional sync ✅
**What**: Tasks in MIND mirror to iOS Reminders and vice versa. Use
EventKit's EKReminder API. Sync on app foreground. **Acceptance**:
create task in MIND → appears in Reminders within 30s. Check off in
Reminders → MIND task shows completed.
Shipped 2026-05-19: new `RemindersKit` module (`RemindersStore` actor
wrapping `EKEventStore.requestFullAccessToReminders` + fetch/create/
update, pure `RemindersSyncEngine` driving the diff with id-pairing,
title-fallback binding and a "completion-beats-open" tie-breaker).
`Node.reminderExternalID` stores the paired `calendarItemIdentifier`.
`MINDApp` runs `runRemindersSyncIfEnabled()` on `.active` scenePhase
behind a `MINDPreferences.remindersSyncEnabled` opt-in (default off).
Settings → Préférences gains a localized "Synchroniser les Rappels"
toggle that triggers the EventKit prompt on first enable. Three new
breadcrumbs: `reminders.sync.applied`, `reminders.sync.noop`,
`reminders.access.denied`. 15 new tests in `RemindersSyncEngineTests`
lock the diff matrix; 174 total tests, 0 failures (was 159 in v0.9).
Screenshot at `mind/screenshots/v0.10.png` shows the host app
launching clean — no permission prompt fires because the opt-in is
off by default, exactly as the privacy contract requires.

---

## Chapter 2 — Public beta polish (v0.11 → v0.20)

Polish wave before opening the TestFlight to 50+ external testers.

### v0.11 — Notion sync (one-way: MIND → Notion) ✅
**What**: Settings → "Notion sync". Mehdi creates an internal
integration at notion.so/my-integrations once and pastes the
integration token into MIND — token stored in Keychain
(`app.mind.ios.notion`). Database ID pasted into a second field,
persisted in App-Group UserDefaults. Audits export to that database
via `POST /v1/pages` when "Sync to Notion" is tapped on the export
sheet. OAuth deferred to v0.11.1 because MIND is solo-user — the
integration token route ships the same feature in one commit without
client ID/secret plumbing or a callback URL. **Acceptance**: token
validates against `/v1/users/me`, audit export creates a Notion
page with all sections (synthesis, quick wins, bets, hidden risks,
pitch). Shipped 2026-05-19: paste-integration-token approach
(NotionKit module, Settings UI, AuditSheet sync button, 9 pure
builder tests).

### v0.12 — Linear sync (audit → Linear projects) ✅
**What**: Audit's "Quick wins" can be one-tap-converted to Linear
issues in a chosen project. Bulk action: "Export all QW to Linear"
creates one issue per QW with priority based on `impact` field.
**Acceptance**: 3 QW → 3 Linear issues with correct titles + labels.
Shipped 2026-05-19: paste-personal-API-key approach (LinearKit
module, Settings team picker, AuditSheet per-QW + bulk push,
11 pure builder + LinearTeam tests).

### v0.13 — Contacts integration ✅
**What**: Capture-from-contact: long-press a contact in iOS Contacts →
"Add to MIND" share extension creates a `person` Node with name +
email + phone + company. **Acceptance**: extension visible on contact
detail, node created with all fields.
Shipped 2026-05-19: broadened MINDShareExtension activation rule with
`NSExtensionActivationSupportsVCardWithMaxCount=1`, vCard parsing via
`CNContactVCardSerialization` in `ShareViewController`, framework-free
`ShareInbox.Payload.contactPayload(...)` pure builder in GraphCore
(backward-compatible JSON codable so older queues decode as `.link`),
host-side `createPersonNode(...)` that tags the resulting `person`
Node with the email-domain. 12 `ShareInboxContactTests` + 2
`LocalizationTests` lock the contract.
Deferred to v0.13.1: in-app Contacts picker (Settings → "Importer un
contact") — the share sheet path covers the headline acceptance, an
in-app picker is a convenience layer.

### v0.14 — Mail capture (Share Extension) ✅
**What**: Extend the share extension to handle email content. User
shares an email → MIND creates a `mail` Node with subject as title,
body as content, sender's email extracted to tags. **Acceptance**:
sharing from Mail.app creates a clean Node with all fields.
Shipped 2026-05-19: pure RFC-822 MailParser routes Mail.app shares into a `.mail` Node via the share extension; tolerant decoder defaults unknown kinds to `.link` for forward compat.

### v0.15 — Knowledge graph visualization (interactive) ✅
**What**: New tab `Graph` between Notes and Clients. Force-directed
graph layout (use SwiftUI Canvas + custom physics) showing Nodes as
circles + Edges as lines. Zoom, pan, tap a node → NodeDetailView.
Colour by kind. **Acceptance**: 50-node graph renders smoothly at
60fps, tap navigation works.
Shipped 2026-05-19: SwiftUI Canvas + pure-function `GraphPhysics.physicsStep` (spring + Coulomb + damping + bounds clamp), pinch zoom 0.5…3.0, drag pan, tap-routing to NodeDetailView via 20pt threshold, 200-node cap with "Afficher plus" CTA, FR/EN strings + 9 physics tests locking the simulation contract.

### v0.16 — Auto-summarization weekly digest ✅
**What**: Every Sunday evening, on-device Foundation Models generates
a weekly digest: "5 things you captured this week", "1 audit completed",
"X hours of focus". Surfaces as a non-disruptive Home card.
**Acceptance**: digest generated, accurate counts, opens an
expandable detail view.
Shipped 2026-05-19: pure `WeeklyDigestBuilder.compute(nodes:focusSessions:asOf:)` + `WeeklyDigest` value type in App, async `OnDeviceIntelligence.weeklyNarrative(_:)` extension hitting LanguageModelSession with FR instructions (soft-fails to nil), HomeView LiquidCard with three monospaced columns + italic narrative (Sun/Mon-only gate, DEBUG override for vision verify), `WeeklyDigestSheet` with summary card + per-day captures + focus session list (tap → NodeDetailView), 11 new xcstrings keys FR/EN, 3 telemetry breadcrumbs (`digest.rendered`, `digest.narrative.generated`, `digest.detail.opened`), 8 pure tests locking the builder contract (empty / window filter / focus sum / highlight sort+cap / audit separation / reference cutoff slide / blank-title skip / withNarrative).

### v0.17 — Daily morning brief ✅
**What**: Every morning at 7am (user-configurable), generate a brief
combining today's calendar + open tasks + last 3 captures + a focus
suggestion. Push notification with summary, tap → full brief view.
**Acceptance**: notification fires at the set time, brief is concrete
and actionable.
Shipped 2026-05-19: pure `DailyBriefBuilder.compute(today:tasks:recentCaptures:lastWeekFocusHours:asOf:)` returns a `DailyBrief` (date / calendarEventCount / openTaskCount / recentCaptureTitles / focusSuggestionMinutes / headline) with 4-branch FR/EN headline rules + focus minutes clamped to [15, 90] (pomodoro 25 default on zero history), `@MainActor DailyBriefScheduler` in the Settings module registers a daily `UNCalendarNotificationTrigger` (id `app.mind.ios.dailyBrief`) wired into `MINDApp.init()` + `.active` scenePhase, `dailyBriefEnabled` / `dailyBriefHour` opt-in toggle + 6h/7h/8h/9h picker in Settings → Préférences, HomeView "Brief du matin" card (5h-11h window, DEBUG always-on for vision verify) + `DailyBriefSheet` (hero headline, today's events, open tasks tap-to-toggle, recent captures, focus suggestion + "Démarrer maintenant" CTA), `mind://brief` URL scheme + RootView `.onOpenURL` posting `.mindOpenDailyBrief` notification, 21 new FR/EN xcstrings keys (`brief.headline.*` / `brief.notification.*` / `brief.detail.*` / `settings.brief.*` / `brief.sheet.start.focus`), 5 telemetry breadcrumbs (`brief.scheduled` / `brief.opened` / `brief.deepLink.opened` / `brief.focus.started.from.brief` / `brief.rendered`), 11 pure tests locking every headline branch + the focus-clamp + the no-history pomodoro fallback + the recent-capture cap + the defensive completed-task filter.

### v0.18 — Voice cloning for read-back (AVSpeechSynthesizer + Apple's neural voices) ✅
**What**: On any Node, "Listen" button that reads the content with
the highest-quality Apple neural voice (Siri Natural). Useful for
long audits while driving. **Acceptance**: audio plays via AirPods,
pause/resume works, locks screen continues playback.
Shipped 2026-05-19: new `@MainActor @Observable VoicePlayer` singleton in `mind/App/Sources/VoicePlayer.swift` wraps `AVSpeechSynthesizer`, activates `AVAudioSession` as `.playback` / `.spokenAudio` (mix + duck others) so playback continues on lock + AirPods, picks the highest-quality voice via `preferredVoice(forLocale:)` (premium > enhanced > default, then root-language fallback, then `en-US`), populates `MPNowPlayingInfoCenter` with title/artist/duration/elapsed (duration estimated at 200 chars/sec) and registers `play` / `pause` / `togglePlayPause` / `stop` on `MPRemoteCommandCenter` so the lock-screen and AirPods double-tap work. A nonisolated `SynthesizerDelegate` shim forwards every callback (`didStart` / `didFinish` / `didCancel` / `willSpeakRangeOfSpeechString`) back to `MainActor` via `Task { @MainActor in }` to satisfy Swift 6 strict concurrency. NodeDetailView (`mind/App/Sources/NodeDetailView.swift`) gains a speaker-glyph "Écouter" button in the header (icon swaps to `speaker.slash.fill` while reading) and a Liquid Glass mini-bar at the bottom showing a live progress capsule + stop CTA whenever the open node is the one reading. 3 new FR/EN xcstrings keys (`node.action.listen` = "Écouter" / "Listen", `node.action.stop.listening` = "Arrêter la lecture" / "Stop listening", `node.voice.playing.banner` = "Lecture en cours…" / "Reading aloud…"). 4 telemetry breadcrumbs (`voice.play.started` with voice ID + quality + locale + char count, `voice.play.completed`, `voice.play.cancelled`, `voice.play.failed`). `UIBackgroundModes` already carried "audio" from v0.6 so no `Project.swift` change. 12 new tests in `VoicePlayerTests` lock the pure helpers — estimated-duration formula (200 chars/sec, zero-input guard), voice selection priority chain (`bestVoice(forExactLocale:)` returns premium when available, falls to enhanced, locale-matches), locale fallback to `en-US` for unknown tags, `qualityName` labelling for all 3 levels + nil, empty-text and whitespace-only early-return contracts, `stop()` idempotency + state reset, `pause()` / `resume()` guards when nothing is playing. Build SUCCEEDED. Screenshot at `mind/screenshots/v0.18.png` shows the host app launching clean — Listen button + mini-bar only render in NodeDetailView with a navigated node, which matches the documented vision-verify bar (host-launches-clean).

### v0.19 — OCR for photos (VNRecognizeTextRequest) ✅
**What**: Capture from photo: user picks a photo (a whiteboard, a
business card, a screenshot) → MIND OCRs it and creates a Node with
the extracted text as content. **Acceptance**: French + English
handwriting both recognised, photo attached to the Node.
Shipped 2026-05-19: new `enum OCRService` in `mind/Modules/Capture/Sources/OCRService.swift` wraps `VNImageRequestHandler` + `VNRecognizeTextRequest` behind `static func recognizeText(from imageData: Data, languages: [String] = ["fr-FR", "en-US"]) async -> OCRResult` with `recognitionLevel = .accurate` + `usesLanguageCorrection = true`. The continuation is single-resume guarded by a captured `resumed` Bool so Vision's "both throw AND completion-fire on corrupt input" double-callback path doesn't trip a fatal CONTINUATION MISUSE — a regression `OCRServiceTests.test_recognizeText_corruptData_returnsEmptyResult_noCrash` pins. Soft-fails to `OCRResult(text: "", blocks: [], confidence: 0)` on empty input + every Vision error. `OCRResult` is `Sendable + Equatable`; `OCRBlock` keeps the Vision-normalised-coord bbox + per-block confidence for future overlay rendering. QuickCaptureSheet (`mind/Modules/Capture/Sources/QuickCaptureSheet.swift`) gains a third 56×56 Liquid Glass action button (`photo.fill` glyph, iris tint, `.ultraThinMaterial` fill) sitting between the mic and the Capture CTA — tap fires the system `PhotosPicker` (`.images`, `.shared`), the `.onChange(of: selectedPhoto)` calls `handlePhotoSelection`, which pulls the binary via `loadTransferable(type: Data.self)`, kicks off `OCRService.recognizeText` off the main thread, appends the recognised text to the editor (or the localized `capture.photo.empty.fallback` line when Vision returned nothing). The label closure is factored into a fileprivate `PhotoPickerLabel: View` consuming a `@Binding var isRunning: Bool` so the spinner ↔ glyph swap survives Swift 6 strict-concurrency's `@escaping () -> Label` Sendable-closure rule. `save()` writes the raw photo bytes under `~/Documents/captures/<uuid>.jpg` and pins the `file://…` URL on `Node.sourceURL`; the Node kind stays `.capture`. 4 new FR/EN xcstrings keys (`capture.photo.button` = "Capturer une photo" / "Capture a photo", `capture.photo.ocrInProgress` = "Lecture de la photo…" / "Reading the photo…", `capture.photo.ocrComplete` = "Texte extrait de la photo" / "Text extracted from the photo", `capture.photo.empty.fallback` = "Aucun texte reconnu sur cette photo." / "No text recognised on this photo."). 5 MINDTelemetry breadcrumbs (`capture.photo.picked`, `capture.ocr.started` with byte count, `capture.ocr.completed` with char count, `capture.ocr.failed`, `capture.ocr.charCount` data-payload). `NSPhotoLibraryUsageDescription` already shipped from v0.0 so no Project.swift Info.plist drift. 7 new `OCRServiceTests` lock the API: empty-Data short-circuit, corrupt-Data soft-fail without CONTINUATION MISUSE, empty-observation assembler returning zero confidence, `OCRResult` + `OCRBlock` Equatable round-trip on identical inputs, inequality on different text, and single-language thread (`["en-US"]`) doesn't crash. `LocalizationTests` extended with `test_capturePhotoStrings_resolveBothLanguages` so FR never silently falls back to EN. Capture module added to `MINDTests` target dependencies. Total tests: 293 (up from 286), 0 failures, 12 skipped. Build SUCCEEDED on iPhone 17 Pro simulator. Screenshot at `mind/screenshots/v0.19.png` shows the host app launching clean — the Photo button only renders inside QuickCaptureSheet which matches the documented vision-verify bar (host-launches-clean).

### v0.20 — First public TestFlight beta ✅
**What**: Open the TestFlight to 50 external testers via the Apple
beta link. Add a `Beta` badge to the About section. Surface a
"Send feedback" link via FB Reporter. **Acceptance**: 50-tester
distribution active, in-app feedback link opens TestFlight feedback.
Shipped 2026-05-19: new `public static func SettingsView.isBetaVersion(_:)` — a pure, side-effect-free semantic-version compare returning `true` for any pre-1.0 short version string (`0.20.0`, `0.999.999`, `0.0.1`) and falling through to `true` on malformed / fallback `"—"` input so dev / preview / test bundles still surface the beta UI. `public static var SettingsView.isBetaBuild` wires the helper to `Bundle.main`'s `CFBundleShortVersionString`. **Beta badge** (`about.beta.badge` = "BETA" / "BÊTA") pinned at the top of Settings → About on every pre-1.0 build — small iris-filled capsule with white uppercase-tracking text, matches Liquid Glass tone. **Beta section** (`settings.beta.section`) inserted just above About with two rows: "Send feedback via TestFlight" (`settings.beta.feedback.button`) opens the universal `https://testflight.apple.com/v3/contact-developer` URL via `@Environment(\.openURL)` — iOS intercepts inside a beta and routes to the in-app screenshot+device-info flow; "Join the beta" (`settings.beta.join.button`) opens `https://testflight.apple.com/join/MINDBETA` (placeholder Mehdi swaps with the real public link in App Store Connect). Both rows hide the moment `isBetaBuild` flips to false. **Welcome banner on HomeView** — Liquid Glass card with `flask.fill` glyph, FR/EN headline ("Tu es dans la beta de MIND"), one-line subtitle, primary CTA opening the TestFlight feedback URL, secondary "Plus tard" dismiss. Stored as `@AppStorage("mind.beta.banner.dismissed") private var betaBannerDismissed: Bool` so the banner is one-time per device, but the whole render gate is `SettingsView.isBetaBuild && !betaBannerDismissed` so the 1.0.0 release auto-hides it for everyone. **`MINDTelemetry` breadcrumbs**: `beta.banner.dismissed`, `beta.feedback.opened` (with `surface=home.banner` payload from the HomeView tap and `surface=settings` from the Settings row tap), `beta.join.opened`. **8 xcstrings keys** added FR + EN: `about.beta.badge`, `settings.beta.section`, `settings.beta.feedback.button`, `settings.beta.feedback.subtitle`, `settings.beta.join.button`, `settings.beta.join.subtitle`, `home.beta.banner.title`, `home.beta.banner.subtitle`, `home.beta.banner.cta`, `home.beta.banner.dismiss`. **12 new `BetaBuildTests`** lock the contract: pre-1.0 strings (`0.5.0`, `0.0.1`, `0.999.999`, `0.20.0`) → true; 1.x / 2.x → false; malformed input (empty, `"—"`, `"0.5"`, `"0"`, `"alpha"`) → true. `LocalizationTests` extended with `test_betaStrings_resolveBothLanguages` (13 asserts). Total tests: 306 (up from 293), 0 failures, 12 skipped. README gains a "Beta status" section explaining the join path + the in-app entry points, and a "Reporting bugs" section ranking TestFlight feedback > GitHub issue. Build SUCCEEDED on iPhone 17 Pro simulator. Screenshot at `mind/screenshots/v0.20.png` shows the beta welcome banner rendering above the search pill on HomeView (iris flask, headline, subtitle, "Send feedback" CTA, "Later" dismiss), the greeting card untouched, Deep Focus card visible below — the v0.20 acceptance criteria met end-to-end code-side; Mehdi flips the actual 50-tester distribution toggle in App Store Connect.

---

## Chapter 3 — Multi-device (v0.21 → v0.30)

Expand from iPhone-only to the full Apple device family. Every
device reads the same CloudKit graph.

### v0.21 — MIND Client Portal Generator ✅
**What**: New module `ClientPortalKit` that turns any completed
`AuditReport` into a self-contained premium HTML static site
(`ClientPortalArchive` = `[String: Data]` map of relative paths →
bytes), written to `Documents/client-portals/<slug>-<date>/` by a
`PortalWriter` actor. The HTML is cinematic — full-viewport hero
with parallax, six SVG circular gauges animated on scroll via
`IntersectionObserver`, Liquid Glass aesthetic via `backdrop-filter`
+ iris → navy → black gradient, scroll-snap timeline for strategic
bets, alert-style hidden-risks cards, pitch + contact + footer.
Zero JS framework, inline CSS, single `index.html` file under 80 KB
gzipped. Respects `prefers-color-scheme` and `prefers-reduced-motion`.
A new row in the AuditSheet ExportSheet ("Générer Client Portal")
triggers the build, then surfaces a success sheet with "Open in
Files" + "Share folder" buttons (UIActivityViewController). Mehdi
drag-drops the folder onto Vercel / Cloudflare Pages and his client
gets a beautiful audit URL in 30 seconds. **Acceptance**: tap
generates the folder, the `index.html` renders cleanly in Safari,
contains the client name + overall score + every quick win +
strategic bet + hidden risk + pitch, and the file weight stays
under the locked 200 KB ceiling.

**Deferred to v0.21.1**: the original "Apple Watch focus
complication" idea (new MINDWatch target, WatchOS complication
showing the live remaining time, CloudKit-synced
`FocusSessionRecord`). Worth shipping once the Apple Developer Watch
provisioning is set up; the encoder/decoder scaffolding from the
previous Watch attempt is stashed locally for re-use.

Shipped 2026-05-19: new `ClientPortalKit` module wires four pure types — `BrandSettings` (accent colour + consultant identity + optional Calendly URL + optional consultant photo data-URL-embedded), `ClientPortalArchive` (`[String: Data]` + `folderSlug`, precondition-guards `index.html`), `ClientPortalBuilder` (Foundation-only entry point delegating to `HTMLTemplates`, plus a pure `makeSlug(clientName:date:)` helper folding diacritics + collapsing punctuation + falling back to `client-…`), and `HTMLTemplates` (every section: hero w/ parallax gradient + grain + scroll glyph, scoring grid w/ 6 SVG circular gauges animated via `IntersectionObserver`-set CSS custom property `--gauge-pct`, synthesis prose w/ light-markdown renderer covering `# / ##` headings + `**bold**` + `*italic*` + bullet lists + paragraphs, quick wins responsive grid w/ impact pill + effort label + perspective hover lift, strategic bets `scroll-snap-type: x mandatory` timeline, alert-style hidden-risks grid w/ severity badge + red-tinted gradient backdrop, full-bleed pitch quote w/ consultant byline + initials-or-portrait avatar, contact CTAs w/ Calendly + mailto, footer w/ wordmark + timestamp; all in one ~3 KB inline CSS w/ `prefers-color-scheme: light` token swap + `prefers-reduced-motion` opt-out + Apple system font stack w/ Inter fallback via Google Fonts preconnect + dark gradient iris → navy → black + `backdrop-filter: blur(20-24px)` Liquid Glass cards) — plus an actor `PortalWriter` that drops the archive under `Documents/client-portals/<slug>-<date>/` (intermediate dirs auto-created, sorted-paths iteration for stable on-disk write order, `MINDTelemetry.info("clientPortal.written")` breadcrumb on success). The new AuditSheet ExportSheet row ("Générer le portail client", iris `globe.americas.fill` glyph + `sparkles` action button) is always visible (no token / opt-in), runs the build off the main actor inside a `Task { }`, then surfaces `PortalSuccessSheet` (`PortalShareItem` Identifiable wrapper) with two CTAs — "Open in Files" via `shareddocuments://`-rewritten URL handed to `UIApplication.shared.open(_:)`, "Share folder" via SwiftUI's native `ShareLink(item: folderURL)` so the user can AirDrop / Save to Files / Messages the folder. 8 new FR/EN xcstrings keys (`audit.export.portal.title|subtitle|error.title|success.title|success.body|success.openInFiles|success.share`). 5 telemetry breadcrumbs (`clientPortal.generated` on archive build, `clientPortal.written` on writer success, `clientPortal.write.failed` on writer error, `clientPortal.opened` on Open-in-Files tap, `clientPortal.shared` on Share-folder tap). Tests: 16 new in `ClientPortalBuilderTests` (archive shape contract, page-weight ceiling under 200 KB on a heavy report, slug lowercase/dashes/diacritics-strip/punctuation-collapse/empty-fallback, content surface for client name + overall score + every quick win / strategic bet / hidden risk / pitch, hidden-risks-section omitted when empty, brand swap surfaces in hero+pitch, `prefers-color-scheme` + `prefers-reduced-motion` honored, determinism for identical inputs, XSS guard escaping `<script>` tags in the client name, light-markdown renderer covering headings + bullet lists + bold) and 4 in `PortalWriterTests` (folder + index.html on disk, intermediate dir auto-creation, nested asset path with sub-folders, default destination root contract). LocalizationTests extended with `test_clientPortalStrings_resolveBothLanguages` (14 asserts FR + EN). 330 tests total, 12 skipped, 0 failures (was 306 in v0.20). Build SUCCEEDED on iPhone 17 Pro simulator. Screenshot at `mind/screenshots/v0.21.png` shows the host app launching clean — the Client Portal row only renders inside AuditSheet → ExportSheet after a real audit completes, which matches the documented vision-verify bar (host-launches-clean). A sample portal HTML (26 KB, well below the 80 KB target) generated for an Acme Corp / Mehdi Nafaa brand pair lives at `mind/screenshots/v0.21-portal.html` — open in any browser to inspect the Liquid Glass aesthetic end-to-end.

### v0.22 — Live Audit Broadcasting ✅
**What**: Client opens a URL on their laptop while Mehdi runs the
audit from his iPhone. They watch the audit happen live — 14 probes
lighting up green/red as they complete, scoring gauges animating from
0 to value, synthesis appearing word-by-word. New `LiveBroadcastKit`
module exposes `LiveBroadcastWriter` (actor) + `LiveBroadcastState`
(Codable). Every probe transition mirrors to
`~/Documents/live-broadcasts/<token>/state.json`; an `index.html`
template polls that file every 800ms via `fetch` and re-renders the
hero / probe grid / scoring gauges / typewriter synthesis. Mehdi
exposes the folder via `cloudflared tunnel`, `ngrok`, `tailscale
serve` or by drop on Vercel — no MIND backend. AuditSheet ships a
"📡 Diffuser en direct" toggle that, when armed before launch, mints
a 16-byte hex token, generates the static HTML, attaches a
`LiveBroadcastSession` to the AuditController, then presents a
share sheet with the broadcast URL + QR code + copy button + deploy
hint. **Acceptance**: a generated broadcast renders end-to-end in
Safari via `npx serve`, every probe transitions live, final state
shows the full report. Watch voice capture deferred to v0.22.1.
Shipped 2026-05-19: new `LiveBroadcastKit` module — `LiveBroadcastState` (Codable wire type, ISO 8601 + sorted-keys canonical encoder, declares `Phase` + `ProbeLifecycle` enums for `"probing/synthesizing/completed/failed"` + `"pending/running/ok/failed"`), `LiveBroadcastSession` (token + folderURL + suggestedURL value handle), `LiveBroadcastHTMLTemplate` (cinematic single-file dark Liquid Glass viewer — iris/navy radial gradient backdrop with grain + noise overlays, gradient-text hero, status pill with pulse animation, 14 probe cards transitioning grey → blue spinner → green check / red cross, 5 SVG circular gauges animating stroke-dashoffset on scoring landing, typewriter caret on synthesis, CTA card swapping in on completion, footer with last-update time, prefers-reduced-motion honored throughout, JetBrains Mono + SF Pro stack, polling `fetch('./state.json')` every 800 ms, 12.6 KB template under the 50 KB ceiling), `LiveBroadcastWriter` (actor with `create(for:)` minting 32-char lowercase hex token + 7-day garbage-collection sweep + atomic `.write(options:.atomic)` snapshot writes, `update(token:mutating:)` read-modify-write loop with `@Sendable` mutation closure, `close(token:success:)` flipping phase to `completed`/`failed`, `cleanupExpiredBroadcasts(under:olderThan:)` non-throwing GC pass, injectable clock + RNG for deterministic test snapshots, `MINDTelemetry.info` breadcrumbs on every lifecycle edge), `LiveBroadcastMapping` (`ProbeStatus.init(kind:controllerState:durationMs:)` + `LiveBroadcastState.probes(from:)` preserving `ProbeKind.allCases` order), and `LiveBroadcastAdapter` (concrete `AuditLiveBroadcaster` mirroring every controller transition into the JSON snapshot, absorbing IO errors as `liveBroadcast.failed` telemetry rather than sinking the audit). New `AuditLiveBroadcaster` protocol in AuditKit (defined here to avoid a circular module dep) is the inversion point: `runStarted`, `probeStateChanged(kind:state:durationMs:)`, `auditCompleted(report:)`, `auditFailed(message:)`. `AuditController` gains optional `liveBroadcaster` property + per-probe `ContinuousClock` wall-time measurement + broadcaster hooks on every phase edge (run/cancel/complete/fail) with zero overhead when nil. `AuditSheet` ships a "Diffuser en direct" Liquid Glass toggle card on the form; when armed, tapping "Lancer l'audit" mints the writer + session + adapter, presents the new `BroadcastShareSheet` (URL field user can paste a cloudflared / ngrok tunnel into, 200 px `CIQRCodeGenerator` QR with error correction `"H"`, copy-link button with success toast + telemetry breadcrumb, native `ShareLink`, deploy hint with `npx serve` / `cloudflared tunnel` / `tailscale serve` / Vercel guidance, folder-reveal row), then kicks off the audit underneath. New `liveBroadcast.created/updated/closed/failed/shareSheet.opened/url.copied` telemetry breadcrumbs. 11 FR/EN xcstrings keys: `audit.broadcast.toggle.{title,subtitle}`, `audit.broadcast.sheet.{title,subtitle}`, `audit.broadcast.url.{copy,copied}`, `audit.broadcast.qr.title`, `audit.broadcast.deploy.hint`, `audit.broadcast.start.cta`, `audit.broadcast.error.title`. Tests: 14 new `LiveBroadcastWriterTests` (Codable round-trip, hex token format, folder + initial state.json + index.html creation, HTML template polling-script presence, relative `./state.json` path, 50 KB file-size budget, atomic `update(_:mutating:)` persistence, `broadcastNotFound` throw on unknown token, `close` phase flip, JSON escaping safety for quotes + control chars, byte-stable canonical encoder determinism, `ProbeKind.allCases` order preservation in mapping, 30-day-back-dated cleanup removal). `LocalizationTests` extended with `test_liveBroadcastStrings_resolveBothLanguages` (14 asserts). 344 tests total, 12 skipped, 0 failures (was 330 in v0.21). Build SUCCEEDED on iPhone 17 Pro simulator. Screenshot at `mind/screenshots/v0.22.png` shows the host app launching clean on HomeView — the broadcast toggle only renders inside AuditSheet, which matches the documented vision-verify bar (host-launches-clean). A sample broadcast at `mind/screenshots/v0.22-broadcast/abcdef1234567890abcdef1234567890/` (12.7 KB HTML + 1.9 KB state.json, locked in `"synthesizing"` phase with 11 OK probes + 1 failed CDN + 1 running Trustpilot + populated scoring gauges + multi-paragraph synthesis with typewriter caret) lets Mehdi `npx serve` it locally to see the live UX end-to-end.

### v0.22.1 — Watch voice capture ✅
**What**: Watch "Capture" view with mic button → records voice →
transcribes via SFSpeech → creates Node on CloudKit → syncs to iPhone.
**Acceptance**: 10-second voice capture appears on iPhone within
30s.
Shipped 2026-05-20 (pure substrate): the watchOS App target + CloudKit container + SFSpeech-on-watch entitlement remain Apple-side artifacts the agent cannot mint (see prior `MIND_BLOCKER_v0.22.1.md`), so this iteration ships the substrate behind the deferred surface — same model v0.31.1 (Audit forecast) and v1.0-alpha.8 (Health Pulse) used. New `WatchCaptureKit` module: `WatchCaptureRecord` (Codable + Sendable + Hashable + Identifiable value type — id / startedAt / durationSeconds (clamped >= 0) / transcript / origin (`.watch` / `.phoneSimulated`) / status (`.pending` / `.synced` / `.failed`) / foldedNodeID; `markSynced(foldedNodeID:)` + `markFailed()` return flipped copies; `hasUsableTranscript` skips whitespace-only mints; raw enum string values locked stable for on-disk JSON forward compatibility), `WatchCaptureTranscriptAssembler` (pure namespace — `assemble(_:)` strips control chars + collapses whitespace, `assemble(from:)` picks longest fragment from SFSpeech partial array, `deriveTitle(from:maxLength:)` cuts at first sentence ender + truncates with ellipsis + falls back to `"Capture vocale"` for empty input), `WatchCaptureQueue` (actor on-disk persistence under `<root>/watch-capture-queue/<id>.json` — atomic enqueue, idempotent on record.id, `loadAll()` sorts newest-first by startedAt + silently skips non-JSON strays, `pending()` filters by status, `remove(id:)` deletes + throws `recordNotFound` for unknown IDs, `record(id:)` returns nil for unknown), `WatchCaptureNodeBuilder` + `WatchCapturedNodeDraft` (pure derivation — turns a record into a `.capture` Node draft with `["watch"]` tag (+ `"simulated"` when phone-simulated), returns nil for empty transcripts, clamps content to 5000 chars with trailing ellipsis). When the watchOS target finally lands, it writes `WatchCaptureRecord` JSON into the CloudKit-mirrored queue; the iPhone drain reads `pending()` + folds each via the NodeBuilder + flips to `.synced` — substrate ready, surface deferred. Tests: 26 new `WatchCaptureKitTests` cover Codable round-trip, negative-duration clamp, markSynced + markFailed semantics, hasUsableTranscript edge cases, enum raw-value stability, assembler whitespace collapse + control strip + longest-fragment pick + empty-input handling, title sentence-cut + ellipsis truncation + fallback, NodeBuilder draft shape (.capture kind + watch tag + simulated tag for phoneSimulated + nil for empty transcript + content clamp), queue actor enqueue + load + sort + idempotency + pending filter + remove + recordNotFound throw + non-JSON skip + record-by-id nil. 755 tests total (was 729), 15 skipped, 0 failures. Build SUCCEEDED on iPhone 17 Pro simulator. Screenshot at `mind/screenshots/v0.22.1.png` shows the host app launching clean on HomeView — the substrate is data-only (no UI), matching the v0.31.1 / v1.0-alpha.8 / v0.22 host-launches-clean vision-verify bar.

### v0.22.2 — Direct WebSocket broadcasting (Option B) ✅
**What**: Replace the polling JSON+static-HTML pipeline with an
embedded HTTP+WebSocket server inside the iOS app via `NWListener`
(Network framework). State updates push directly to connected
browsers instead of polling. More magic, more fragile — needs the
viewer to be on the same Wi-Fi or expose via tailscale / ngrok.
**Acceptance**: zero-latency probe transitions on a browser
connected to the iPhone's local HTTP server.
Shipped 2026-05-19: new `LiveBroadcastWebSocketServer` actor in LiveBroadcastKit — binds `NWListener` on `127.0.0.1:<port>` (default 8787, `0` requests an ephemeral port returned via `boundPort`), serves the HTML template on `GET /`, upgrades `GET /ws` to a WebSocket via RFC 6455 (computes `Sec-WebSocket-Accept` from `Sec-WebSocket-Key + 258EAFA5-E914-47DA-95CA-C5AB0DC85B11` magic via an inlined pure-Swift SHA-1 implementation so no extra framework import is needed), tracks connected `NWConnection` clients with a 16-client ceiling (503 on overflow), broadcasts `LiveBroadcastState.encoded()` JSON as unmasked text frames (FIN=1, opcode=1, RFC 6455 §5.2 length forms for <126 / 16-bit / 64-bit payloads), caches the last snapshot so newly-connected clients hydrate immediately, prunes failed/cancelled connections via `stateUpdateHandler`, and posts `liveBroadcast.ws.{ready,started,stopped,clientConnected,clientFailed,encodeFailed}` telemetry. New `LiveBroadcastWebSocketAdapter` concrete `AuditLiveBroadcaster` (mirrors the polling adapter but pushes through the server instead of the disk writer — keeps cached state under `NSLock` so simultaneous `MainActor` callbacks + connection-queue prune events stay consistent). New `LiveBroadcastHTMLTemplate.renderWebSocket(clientName:host:)` variant — same Liquid Glass dark cinematic CSS as the polling template but the trailing `<script>` opens a `new WebSocket(location.protocol === 'https:' ? 'wss:' : 'ws:' + '//' + location.host + '/ws')` and re-renders on `message` events; auto-reconnects every 1 s on `close`/`error` with the status pill flipping to "Reconnexion…". Public `HTTPRequestHead` parser ships alongside for unit testing the upgrade detection (`isWebSocketUpgrade(forPath:)` accepts `Connection: keep-alive, Upgrade` as browsers actually send). Both pipelines (polling + WebSocket) can run side by side — the WebSocket layer doesn't replace the disk writer, it offers a zero-latency alternative for same-LAN viewers. Tests: 14 new `LiveBroadcastWebSocketServerTests` cover frame encoding (short / 16-bit / mask-bit-clear), `Sec-WebSocket-Accept` derivation (RFC 6455 sample `s3pPLMBiTxaQ9kYGzzhZRbK+xOo=` + input-dependence), HTTP request parsing (case-insensitive header lookup, mixed `Connection` header detection, plain GET rejection), URL helper (`makeURL(host:port:)`), WebSocket template variant (no polling references, contains `new WebSocket(`, stays under 50 KB), server end-to-end (boots on ephemeral port, raw `GET /` returns the WebSocket HTML), broadcast-without-clients is safe (no-op when no clients yet, snapshot cached for next connect), and adapter lifecycle mirroring (initial probes pending → probe ok → audit completed with scoring + synthesis + pitch). 424 tests total, 12 skipped, 0 failures (was 410 in v0.26). Build SUCCEEDED on iPhone 17 Pro simulator. Screenshot at `mind/screenshots/v0.22.2.png` shows the host app launching clean on HomeView — the WebSocket server only spins inside the AuditSheet flow, matching the v0.22 host-launches-clean vision-verify bar.

### v0.23 — Generative Before/After Site Mockups ✅
Shipped 2026-05-19: new `RedesignMockup` value type lives in AuditKit alongside `AuditReport.mockups: [RedesignMockup]` (optional, defaults to `[]`, backward-compatible custom Codable decoder so payloads serialised before v0.23 still round-trip). New `RedesignMockupSource` protocol declared in AuditKit is the inversion point the controller plugs into. New `RedesignMockupPrompt` (pure namespace) + `RedesignMockupGenerator` (actor) + `RedesignMockupSourceAdapter` (conforms VisualKit's generator to AuditKit's protocol) live in VisualKit, reusing the existing `OpenAIImageClient` + `OpenAIAPIKeyStore` so the OpenAI key + endpoint configuration stay centralised. `RedesignMockupGenerator.generate(…)` fans out the 3 prompts in parallel via TaskGroup with per-mockup soft-fail (one rate-limited request leaves the carousel with 2 tiles instead of nuking the batch); telemetry breadcrumbs (`redesignMockup.generation.started/completed/failed`) bounce onto MainActor through async shims so the actor stays off the main thread. `AuditController` gains `mockupSource: RedesignMockupSource?` + `kickOffMockupGeneration(source:report:)` that fires a detached Task after the report lands and folds the result back into `report.mockups` via a `generatedAt` guard so a fresh audit in flight doesn't get poisoned. `AuditSheet` adds a "Vision : votre site, refait" section between "Synthèse" and "Quick Wins" with 3 branches — populated → horizontal scroll-snap carousel of 320×180 `LiquidCard`-tinted tiles tap → full-screen modal showing the high-res PNG + the quick-win brief; empty + key configured → 3 shimmer skeletons + "Génération en cours…" progress label; empty + key missing → soft hint card pointing to Settings (rendered only when there's at least 1 quick win to visualize). `startAudit` re-reads `OpenAIAPIKeyStore` on every run so a freshly pasted key takes effect on the next audit without relaunch. `HTMLTemplates.visionSection(report:)` injects a matching gallery into the Client Portal HTML between Synthesis + Quick Wins — each mockup embedded as a `data:image/png;base64,…` URL so the portal folder stays single-file self-contained; gallery uses the same `scroll-snap-type: x mandatory` pattern as the Strategic Bets timeline for visual consistency. 11 KB of Vision CSS (gallery + card + media + caption) sits next to the Quick Wins block. 4 new MINDTelemetry breadcrumbs (`redesignMockup.generation.started/completed/failed/aborted` + `redesignMockup.tapped`). 6 new FR/EN xcstrings keys (`audit.vision.section.title`, `audit.vision.generating`, `audit.vision.empty.keyMissing`, `audit.vision.tap.detail`, `portal.vision.section.title`, `portal.vision.caption.prefix`). Tests: 11 new `RedesignMockupPromptTests` lock the pure builder — client name + host surface in the body, quick-win title + detail thread through verbatim, iris/aqua hex palette (`#5E5BD8` / `#5EE9D8`) anchored in every prompt, FR copy-language hint preserved for every persona, "no logos, no UI chrome" tail constraint, fallback prompt grounds in the prospect when client name is empty, `selectQuickWins` truncates at 3 + preserves priority order + empty-input → empty-output, determinism for identical inputs, `derivedMockupTitle` strips trailing punctuation + truncates at 48 chars with ellipsis. `LocalizationTests` extended with `test_redesignVisionStrings_resolveBothLanguages` (12 asserts FR + EN). 356 tests total, 12 skipped, 0 failures (was 344 in v0.22). Build SUCCEEDED on iPhone 17 Pro simulator. Screenshot at `mind/screenshots/v0.23.png` shows the host app launching clean on HomeView — the Vision section only renders inside AuditSheet after a real audit completes, which matches the documented vision-verify bar (host-launches-clean). Sample portal at `mind/screenshots/v0.23-portal.html` (10 KB) shows the structure end-to-end with placeholder SVG rectangles standing in for the GPT Image 2 PNGs — open in any browser to inspect the Liquid Glass gallery aesthetic.

**What**: After an audit completes, generate 3 "after redesign"
mockup images via OpenAI GPT Image 2 visualizing what the site
would look like AFTER applying the top 3 quick wins. Embed them
inline in the AuditSheet completed view AND in the Client Portal
HTML (v0.21). When the client sees "here's your site today" →
swipe → "here's your site in 3 months with Mehdi's recommendations
applied", that's the close. Reuses VisualKit's existing
`OpenAIImageClient` + `OpenAIAPIKeyStore`. New
`RedesignMockupGenerator` actor + pure `RedesignMockupPrompt`
struct, soft-fail per mockup (one failure ≠ all fail), `medium`
quality default with `high` exposed as opt-in. `AuditReport` gains
optional `mockups: [RedesignMockup]` with a backward-compatible
default. AuditSheet adds a "Vision: votre site refait" section
between "Synthèse" and "Quick Wins" — 3 skeleton cards during
generation, then a horizontal scroll-snap carousel of 320×180
mockup cards, tap → full-screen modal. Client Portal HTML gains a
matching "Vision" section with base64-embedded scroll-snap
gallery so the portal stays single-folder self-contained. If
OpenAI key not configured, both surfaces hide the section
gracefully (AuditSheet shows a "Connecte ta clé OpenAI dans
Settings" hint, portal omits the section). **Acceptance**: with
an OpenAI key, completing an audit surfaces 3 mockups in the
AuditSheet + 3 mockups in the generated portal HTML; without a
key, the AuditSheet shows the hint and the portal is unchanged.

**Deferred to v0.23.1**: Mac Catalyst app — enable Mac Catalyst on
the App target. Optimise window sizing, menu bar with
capture/focus/audit. Sidebar always visible. App runs on Mac, menu
bar shortcuts work, window resizes cleanly.

**Deferred to v0.23.2**: WKWebView headless render of the current
site → PNG → pass to GPT Image 2 as reference image so the
"before" state grounds the "after" generation in the actual
layout/palette. For now the generator works from prompt only,
which is the right MVP cut since brand consistency is captured by
the iris/aqua tokens already embedded in the prompt.

### v0.24 — Audit Battle Mode ✅
**What** (PIVOT 2026-05-19 from iPad Stage Manager polish — that
work is deferred to v0.24.1): one URL in, three competitors auto-
suggested from a hardcoded SaaS table, four audits run in parallel,
results render as a 4-way radar chart + per-metric podium showing
who wins which axis. The client-portal HTML gains a new "Battle
Mode" section (CSS-only SVG radar + podium row, no JS chart lib)
that sits above the synthesis when a battle is attached.
**Acceptance**: HomeView audit card surfaces a secondary "Mode
Battle" CTA, BattleSheet shows form → 4 parallel probe cards →
radar + podium, sample 4-way portal renders cleanly.

Shipped 2026-05-19: new `CompetitorLookup` pure enum with a 30-entry
SaaS host → competitors table covering payments / project mgmt /
docs / hosting / design / DB / CRM / analytics / email / support
verticals with `www.`-strip + case-insensitive lookup; new
`BattleController` (`@MainActor @Observable`, fresh AuditController
per participant inside a TaskGroup, soft-fail per participant,
200 ms polling mirror into `participants: [Participant]` so the
SwiftUI cards render running spinners without subscribing to N
inner controllers) + a pure `BattleReport.derive(from:)` that
projects per-metric winners with deterministic first-wins tie
breaking + zero-axis omission + unresolved/failed exclusion; new
`RadarChartView` in DesignSystem (pure SwiftUI Canvas, 6-axis
radar starting at 12 o'clock, one filled+stroked polygon per
series, vertex dots, axis label drawing, value clamping 0-100,
empty-axes guard, .smooth value animations); new `BattleSheet` in
the App layer with three phases (form with primary URL + auto-
suggested chip row + manual add field, running grid of 4
LiquidCards horizontal-scrolled showing the 13 probe dots per
participant in real time, completed view stacking radar card +
per-metric podium with trophy badge + colour-coded legend); the
HomeView `auditCard` now hosts a secondary "Mode Battle" CTA
under the existing single-audit row separated by an iris
divider; `HTMLTemplates` extended with `battleSection(report:)`
(CSS-only SVG radar — 4 polygons, axis rings, axis rays, axis
labels — plus a podium row with trophy + "Gagne" capsule + a
legend chip row) wired through `indexHTML(for:brand:battle:)` so
a battle-aware portal renders the section between the scoring
band and the synthesis prose, with new battle.* CSS in the
inline stylesheet (grid that collapses to single-column at 640px,
Liquid Glass card surfaces, accent-tinted winners). 18 new FR/EN
xcstrings keys (`battle.title|subtitle`,
`battle.form.primary.label|placeholder`,
`battle.form.competitors.label|empty`,
`battle.form.add.competitor`, `battle.form.validation.invalidURL`,
`battle.cta.start`, `battle.running.label`, `battle.radar.title`,
`battle.podium.title`, `battle.winner.badge`,
`battle.legend.failed`, `battle.metric.{overall|performance|seo|
security|brand|mobile}`, `home.battleCard.title|subtitle`). 4
telemetry breadcrumbs (`battle.started` with primary host +
count, `battle.completed` with count + failed count,
`battle.participant.failed` with host + reason,
`battle.exported.portal` exposed via
`BattleController.recordExportToPortal(participantCount:)` for
the future portal-export call site). Tests: 16 new — 5 in
`CompetitorLookupTests` (exact match, www-strip, unknown→empty,
case-fold, table dedupe sanity), 6 in `BattleReportTests`
(2-contender winners derivation per metric, first-wins tie
break, all-zero axis omission, single-participant wins-
everything-non-zero, 4-participants×6-metrics legality bounds,
unresolved+failed excluded), 4 in `RadarChartViewTests` (clamp
range, polygon padding for short series, empty-axes returns
empty, full-score-axis-0 projects to 12-o'clock edge), 1 in
`BattlePortalSampleEmitter` (writes the 30 KB sample HTML +
asserts every critical substring lands). `LocalizationTests`
extended with `test_battleModeStrings_resolveBothLanguages`
locking 10 critical FR + EN strings. 373 tests total, 12
skipped, 0 failures (was 357 in v0.23). Build SUCCEEDED on
iPhone 17 Pro simulator. Screenshot at `mind/screenshots/v0.24.png`
shows the host app launching cleanly. Sample battle portal HTML
at `mind/screenshots/v0.24-battle-portal.html` (29.7 KB) renders
the full versus screen with Stripe vs Adyen vs Mollie vs Checkout
across all six axes — open in any browser to verify the radar
geometry + podium layout end-to-end.

### v0.24.1 — iPad Stage Manager polish ✅
**What** (original v0.24 scope, deferred when Battle Mode took the
slot 2026-05-19): Optimise for Stage Manager — stable window aspect
ratios, keyboard shortcuts for capture/focus, drag-drop URL from
Safari to QuickCapture. **Acceptance**: 6 windows in Stage Manager
don't break layout, ⌘N opens Quick Capture.
Shipped 2026-05-20: new `mind/App/Sources/StageManagerCommands.swift` — pure `StageManagerCommandID` enum (`newAudit`, `selectTab` rawValues used directly as the matching `Notification.Name.rawValue` so the menu DSL and `RootView` .onReceive stay in lock-step through a single source of truth), pure `TabShortcut` value (`home/clients/pipeline/settings` aligned with the Cockpit Studio four-tab MINDTab enum after the v1.0-alpha.1 pivot, 1-indexed `keyDigit` 1-4, `localizedKey` under `command.tab.<rawValue>` namespace, `fallbackTitle` for off-bundle environments, `from(keyDigit:)` round-trip helper), and a `StageManagerCommands: Commands` SwiftUI builder that replaces `.newItem` with a ⌘N "New Audit" entry + a custom `View` menu grouping ⌘1...⌘4 tab-switch entries — each menu pick posts the matching `Notification.Name` on `NotificationCenter.default` so RootView (`selection`) + HomeView (`isAuditing`) can react without `Commands` having to read `@State` directly through the menu DSL. `MINDApp.swift` mounts `.commands { StageManagerCommands() }` + `.defaultSize(width: 1024, height: 768)` + `.windowResizability(.contentMinSize)` on the main `WindowGroup` so Stage Manager tiles inherit a stable 4:3-ish iPad-portrait aspect and don't collapse into matchstick widths when the user pins six MIND windows side-by-side. `RootView` body gains two `.onReceive` blocks: `mindCommandSelectTab` decodes `userInfo["tab"]` into a `MINDTab` (the pivot upgraded `MINDTab` to `String, Hashable` so rawValue init is direct) and `mindCommandNewAudit` flips `selection = .home` so the audit card surface is on screen before HomeView's matching listener flips `isAuditing = true`. HomeView gains a third `.onReceive` for `mindCommandNewAudit` to present the existing `AuditSheet`. 6 new FR/EN xcstrings keys: `command.newAudit`, `command.view.menu`, `command.tab.{home,clients,pipeline,settings}`. 4 telemetry breadcrumbs: `command.selectTab.fired`, `command.selectTab.malformed`, `command.newAudit.fired` + per-tab `data["tab"]` payload. Tests: 12 new `StageManagerCommandsTests` cover command-ID uniqueness + prefix convention, Notification.Name ↔ enum rawValue alignment, keyDigit uniqueness + sidebar ordering + 1-9 validity range, `from(keyDigit:)` round-trip + out-of-range nil, localizedKey namespace, fallback titles non-empty, `Notification.userInfo` round-trip (post → observe → decode), and TabShortcut↔MINDTab rawValue alignment. `LocalizationTests` extended with `test_stageManagerCommandStrings_resolveBothLanguages` (8 FR + EN asserts locking every menu-bar label). 559 tests total, 12 skipped, 0 failures (was 553 in v0.32). Build SUCCEEDED on iPhone 17 Pro simulator. Screenshots at `mind/screenshots/v0.24.1.png` (iPhone 17 Pro — host launches clean on the Cockpit Numelite onboarding) and `mind/screenshots/v0.24.1-ipad.png` (iPad Pro 13" M5 — `defaultSize(1024×768)` honoured, Liquid Glass card adapts cleanly to the wider canvas) — the menu-bar shortcut surface itself only renders when a hardware keyboard is attached, matching the documented host-launches-clean vision-verify bar used by v0.22 / v0.22.2 / v0.23 / v0.25 for conditional / on-demand UI.

### v0.25 — ROI Calculator inline ✅
**What** (PIVOT 2026-05-19 from Vision Pro spatial layout — that
work is deferred to v0.25.1): each Quick Win in an audit gets an
estimated €€€/month revenue impact computed by Claude (conversion
lift × estimated traffic × estimated ARPU). The Client sees, inline
on every QW, an "+€2 400/mo" line above the impact pill and, just
above the Quick Wins section header, a hero "Total ROI estimé"
card with the giant FR-formatted sum + the 12-month annualised
total + a "Méthodologie" button that opens a modal explaining the
formula and the per-confidence breakdown. New
`AuditReport.QuickWin` gains optional
`estimatedMonthlyRevenueImpactEUR: Int?` + `confidence:
ConfidenceLevel?` fields (`.low|.medium|.high`) with a
backward-compatible Codable decoder so reports synthesised before
v0.25 still round-trip. New `ROIEstimator` actor + pure
`ROIPromptBuilder` live in AuditKit, wraps `CloudIntelligence`
with a JSON-mode response, soft-fails to an empty dict on any
error. `AuditController` auto-triggers the estimator after
synthesis lands and folds the per-QW estimates back into
`report.quickWins`. The Client Portal HTML gains a matching giant
hero card right after the scoring section (animated count-up via
vanilla JS + IntersectionObserver) plus the per-QW ROI badge on
each card. **Acceptance**: with an Anthropic key + a real audit,
the AuditSheet completed view shows the ROI line under every QW
and the hero total above the Quick Wins section; without the
estimate landing in time, both surfaces gracefully render the
QWs without ROI badges (the hero card is only mounted when at
least one QW has a non-nil impact). Sample portal HTML at
`mind/screenshots/v0.25-portal.html` shows the hero card + per-QW
badges with placeholder numbers.

Shipped 2026-05-19: new `AuditReport.QuickWin` gains optional `estimatedMonthlyRevenueImpactEUR: Int?` + `confidence: ConfidenceLevel?` fields with a backward-compatible Codable decoder (missing keys round-trip as nil); `quickWins` flipped from `let` to `var` so the controller can mutate per-QW ROI after synthesis. New `AuditKit/ROIEstimator.swift` ships a non-MainActor `actor ROIEstimator` (default `.shared`), a pluggable `CloudIntelligenceHandle` (test seam — `.live` bridges to the `@MainActor CloudIntelligence` through a MainActor-spawned `Task<String, Error>` so the URLSession round trip stays off the actor queue), a `ClientContext` sendable value (`industry / estimatedMonthlyTraffic / estimatedARPU_EUR`, all optional, `.unknown` default), a `ROIEstimate` sendable value, and a pure `ROIPromptBuilder` namespace that turns `(report, context) → prompt` deterministically + parses the JSON response + maps it back to `[UUID: ROIEstimate]`. The prompt caps QWs at `maxQuickWins = 10`, asks Claude for a 0-30k EUR per-win clamp, requests JSON-only output with a strict schema (`{estimates: [{id, monthlyRevenueImpactEUR, confidence, reasoning}]}`), embeds the client/host/persona/scoring + the FR/EN context lines (with "unknown" placeholders when context is nil), and stays byte-stable for identical inputs. `mapPayload(_:into:)` clamps impacts at 30k, drops unknown UUIDs silently, and falls back to `.medium` on unrecognised confidence strings. Three pure aggregation helpers (`monthlyTotalEUR`, `annualisedTotalEUR`, `aggregateConfidence`) are reused by the AuditSheet hero card and the portal HTML hero card so both surfaces always read the same number. `AuditController` gains `roiEstimator: ROIEstimator? = .shared` + `roiClientContext: ClientContext = .unknown` + a `kickOffROIEstimation(estimator:context:report:)` detached Task fired right after `kickOffMockupGeneration`; fold-in path guards on `report?.generatedAt == snapshot.generatedAt` so a stale estimate from a previous audit can't poison a fresh report. Soft-fails the whole batch on any error (missing Anthropic key, network blackout, JSON decode failure) so the audit completion banner is never blocked. Telemetry breadcrumbs: `roi.estimation.started/completed/failed` with host + counts. `AuditSheet` ships a giant Liquid Glass `roiHeroCard(for:)` mounted above the Quick Wins section header only when `ROIPromptBuilder.hasAnyEstimate(in:)` returns true — 48pt FR-grouped total in iris with monospaced digit + content transition, "Projeté sur 12 mois : 224 400 €" subtitle, optional confidence pill (gray/orange/green per level), "Méthodologie" button that opens a `ROIMethodologySheet` (full breakdown of every contributing QW + the formula body). Each `quickWinCard(_:)` now stacks a tiny iris-tinted "+2 400 € /mois" capsule above the existing impact pill via `roiInlineLabel(for:)`. Pure FR-grouped formatter `AuditSheet.roiAmountString(_:)` uses `NumberFormatter` with `fr_FR` locale + NBSP thousands separator so "+18 700 €" reads exactly as Mehdi's audience expects. Client Portal HTML (`HTMLTemplates.swift`) gains a new `roiHeroSection(report:)` between scoring and battle sections — a 56pt gradient-text amount with vanilla-JS ease-out count-up animation (1.4 s, triggered by the existing `IntersectionObserver` when the section enters the viewport, no-op when `prefers-reduced-motion`), the same FR-grouped formatter mirrored in JS via `Intl.NumberFormat('fr-FR')`, an optional FR confidence pill ("confiance : élevée"). Each `quickWinCard(_:_:)` HTML now stacks an aqua-tinted `.win__roi` badge above the title when the estimate is present, with `aria-label` for screen readers. 8 new FR/EN xcstrings keys: `roi.hero.total.label`, `roi.hero.annualized.label` (format string), `roi.confidence.{low|medium|high}`, `roi.per.month.suffix`, `roi.methodology.button`, `roi.methodology.body`, `roi.qw.badge.format` (format string). 4 telemetry breadcrumbs (`roi.estimation.started`, `roi.estimation.completed`, `roi.estimation.failed` with stage payload — `network|encode|decode|kickoff`, `roi.methodology.opened`). Tests: 17 new in `ROIEstimatorTests` (client identity in prompt, all QW titles surfaced, JSON-output instruction locked, industry/traffic/ARPU surface when provided, "unknown" placeholders when nil, `selectQuickWins` caps at `maxQuickWins`, empty input returns empty, deterministic builder for identical inputs, `maxQuickWins` hint stays in prompt body, `mapPayload` folds known IDs / drops unknown IDs / clamps above the 30k cap, aggregation = sum / annualised = × 12 / nils excluded / confidence = min-by-rank) + 4 in `ROIEstimateAggregationTests` (the four contracts the spec literal calls out, separated to make the regression target obvious) + 1 in `LocalizationTests` (`test_roiCalculatorStrings_resolveBothLanguages` locks every FR+EN ROI key) + 1 in `ROIPortalSampleEmitter` (writes the 31 KB sample portal HTML for Acme Fintech with five placeholder QWs summing to "+18 700 €/mois" + asserts critical substrings). 396 tests total, 12 skipped, 0 failures (was 373 in v0.24). Build SUCCEEDED on iPhone 17 Pro simulator. Screenshot at `mind/screenshots/v0.25.png` shows the host app launching cleanly on HomeView — the hero ROI card + per-QW badges only render inside AuditSheet after a real audit completes, which matches the documented vision-verify bar (host-launches-clean). Sample portal at `mind/screenshots/v0.25-portal.html` (31 KB) renders the full ROI hero + per-QW badges + count-up animation for Acme Fintech — open in any browser to verify the cinematic ROI surface end-to-end with placeholder numbers (real estimation requires the Anthropic API key configured in the device's Keychain).

### v0.25.1 — Vision Pro spatial layout (pure substrate) ✅
**What** (original v0.25 scope, deferred when ROI Calculator took
the slot 2026-05-19): Enable visionOS target. Cards float in 3D
space, focus timer becomes a glowing sphere, audit reports float
as readable panels. **Acceptance**: app runs on Vision Pro
simulator, basic interactions work.

Shipped 2026-05-20 (pure substrate): same model as v0.22.1 /
v0.31.1 / v1.0-alpha.8 — lock the value types + the layout math +
the on-disk store now, ahead of the visionOS App target. New
`VisionSpatialKit` module ships four pure surfaces: `SpatialAnchor`
(Codable + Sendable + Hashable 3D point with position clamped to
±10 m + angles wrapped into `[-π, π]` + `translated(byX:y:z:)` +
`facing(_:)` helpers); `SpatialPanel` (Codable + Identifiable
descriptor with `Kind` enum `.focusTimer` / `.auditReport` /
`.noteCard` / `.projectChip` / `.generic`, size clamped to
`[0.05, 4.0]` m, title trimmed to 80 chars, `diagonalMeters`
helper); `SpatialLayoutPreset` (3 cases — `.bento` / `.cinema` /
`.atelier` — with FR + EN display names + FR subtitles, stable
raw values); `SpatialLayoutBuilder` (pure deterministic
`layout(panels:preset:)` — Bento = 3-column grid at z=-1.2m,
Cinema = hero centred at z=-2m with side panels splaying ±60°
alternately left/right and `facing(.origin)` rotating each, Atelier
= focus timer at z=-1m with other panels pushed ±1m horizontal);
`SpatialLayoutStore` actor (per-preset JSON persistence under
`Documents/spatial-layouts/<preset>.json` mirroring `HealthPulseStore`
/ `WatchCaptureQueue` shape, atomic writes, `save` / `load` /
`delete` / `isEmpty` / hydration-across-instances). Module
registered in `Tuist/ProjectDescriptionHelpers/Module.swift` with
zero dependencies (no GraphCore — every anchor / panel is self-
contained). Test target gains `Module.visionSpatialKit` link.
Tests: 29 new `VisionSpatialKitTests` lock the contract — anchor
Codable round-trip + clamp + angle wrap + origin + translate +
facing-yaw direction; panel Codable + size clamp + title trim +
diagonal + anchored helper; builder empty input + Bento 3-panel-
row alignment + 6-panel two-row layout + Cinema hero-centred +
side alternation + Atelier focus-timer-centred + alternating
sides + deterministic for identical input + preserves order &
IDs; preset 3-cases + FR/EN strings non-empty + stable raw
values; store save→load + missing-preset nil + save replaces +
delete + delete missing returns false + isEmpty flips + hydration
across fresh instances over same root. 784 tests total, 15
skipped, 0 failures (was 755 in v0.22.1 — +29). Vision verify at
`mind/screenshots/v0.25.1.png` (host launches clean on the
Cockpit — "Bonjour Mehdi" hero + 4 leads + Projets actifs +
Pipeline visible, Liquid Glass aesthetic intact — substrate
invisible until the future visionOS App target lights up, which
is the documented contract).

### v0.26 — AI Sales Email Generator ✅
Shipped 2026-05-19: new `OutreachKit` module + `OutreachSheet` UI + 3 entry points (NodeDetailView client body, HomeView audit card tertiary row, ClientCard context menu) + 14 pure tests + FR/EN strings.
**What** (pivoted 2026-05-19 from "CarPlay capture" — CarPlay
deferred to v0.26.1 once Apple entitlement lands): outreach engine
that turns any client/prospect Node into 5 cold email variants
written in Mehdi's voice. Each variant is personalised on the
prospect's audit findings + recent activity + industry, tagged with
an angle (ROI / Quick win / Concurrent / Funding / Question), and
exportable to Mail.app via a `mailto:` deep link. **Acceptance**:
new `OutreachKit` module ships with `OutreachEmailGenerator` actor +
pure `OutreachPromptBuilder` + pure `OutreachMailto` URL builder;
new `OutreachSheet` SwiftUI screen renders 5 variant cards with
Copy / Open-in-Mail / Like actions; entry points wired from
`NodeDetailView` (client kind), `HomeView` audit card tertiary
row, and `ClientCard` swipe; 15 FR/EN localizable keys; 13 pure
tests in `OutreachKitTests` (8 prompt-builder + 5 mailto); iOS
Simulator screenshot validates the app launches clean.

### v0.26.1 — CarPlay capture ⏳
**What**: CarPlay scene with a single big "Capture by voice" button.
Same SFSpeech flow as iPhone. Useful for hands-free note-taking
while driving. **Acceptance**: app appears in CarPlay menu, voice
capture creates Node. Blocked on Apple CarPlay entitlement request.

### v0.27 — Lead Scoring Engine ✅
**What**: Every client/prospect Node gets a 0–100 lead score every
render — ICP fit (0–40) + buying signals (0–40) + engagement (0–20)
— with three-tier colour-coded badges (🔥 hot 80+, ☀️ warm 50–79,
❄️ cold <50). ClientsView sorts by score desc by default with a
segmented control for recent / alphabetical, the badge taps into a
breakdown modal explaining the 3 sub-scores + reasoning bullets,
and HomeView gains a "Top leads 🔥" card listing the 3 hottest
non-completed prospects. **Acceptance**: heuristic is pure +
deterministic, breakdown modal opens on tap, sort segmented control
flips order live, Home Top leads card lists 3 hottest with badges.
Shipped 2026-05-19: new `LeadScore` + `LeadTemperature` + `LeadScorer`
in AuditKit (pure heuristic + optional aiEnhanced), 23 new pure
tests in `LeadScorerTests`, 14 new FR/EN localizable keys, README
section added.

### v0.27.1 — Lock Screen widgets ✅
**What**: Lock Screen widgets (circular, rectangular, inline) for
focus timer + quick capture + today's brief. **Acceptance**: all 3
widget styles render correctly on lock screen, tap deep-links into
app. (Deferred from v0.27 to make room for the Lead Scoring Engine
pivot — the score is the load-bearing "who do I call next" signal
that the Lock Screen widgets will eventually surface anyway.)
Shipped 2026-05-20: pure-substrate Lock Screen complication trio
lands behind a single new `LockScreenWidget` registration in
`MINDWidgetsBundle`. New `LockScreenEntrySnapshot` Sendable
Equatable value type + `LockScreenWidgetFormatter` namespace live
in `mind/Modules/GraphCore/Sources/LockScreenWidgetEntry.swift` so
the test target can pin every formatter boundary without linking
WidgetKit (the widget appExtension is sandboxed away from MINDTests).
Three accessory families register: `.accessoryCircular` (brain glyph
+ count dial, 18pt rounded mono glyph for <100, 14pt for >=100,
clamped at 999+ via `LockScreenWidgetFormatter.formatCount`),
`.accessoryRectangular` (brain header + pluralised count + last
Node title or "Tap to capture" empty-state CTA), `.accessoryInline`
("MIND · N thoughts" prefix-branded single line). All three render
through `LockScreenWidgetView` switched on `@Environment(\.widgetFamily)`,
share the same `LockScreenProvider` reading `Node` rows from
`GraphCore.sharedContainer` (sort by `updatedAt` desc, filter to
`note + capture` kinds), and `widgetURL(...)` to `mind://lock` so the
Lock Screen tap deep-links into the host app. Hourly Timeline
refresh policy mirrors `QuickStatsWidget` for snapshot consistency.
Tests: 19 new `LockScreenWidgetFormatterTests` lock every formatter
branch — `formatCount` (zero, single-digit pass-through, two-digit
pass-through, three-digit pass-through, overflow → "999+",
overflow at 12_345, negative defensive → "0"), `rectangularHeader`
(empty graph CTA, singular `1 thought`, plural `N thoughts`,
overflow `999+ thoughts` via the same clamp), `inlineBody`
(always-brand-prefix, singular, plural with count, zero plural),
`deepLinkURL` (absolute string `mind://lock`, scheme `mind`, host
`lock`), value-type round-trips (placeholder constants preserved,
empty preset carries 0+nil, Equatable identical-fields-equal,
Equatable differing-count-unequal). Build SUCCEEDED on iPhone 17
Pro simulator. Vision verify at `mind/screenshots/v0.27.1.png`
shows the host launching clean on the Cockpit — the Lock Screen
surface itself lives behind iOS's Lock Screen customisation flow,
matching the host-launches-clean vision-verify bar used by
v0.22.1 / v0.31.1 / v1.0-alpha.7 / v1.0-alpha.8 for pure-substrate
shipments.

### v0.28 — Discovery Call Prep Dossier ✅
**What** (pivoted from original "Standby mode dashboard", deferred to
v0.28.1): the day before any prospect/client meeting, MIND generates
a 1-pager brief — recent company news, audit findings, attendees +
LinkedIn, 5 calibrated discovery questions, a 30-second elevator
opening in Mehdi's voice. Push notif fires at 7am the morning of the
meeting; tap → modal dossier with per-line "Copier" buttons.
**Acceptance**: pure detection + question + opening builders are
deterministic and FR-only, morning-of notification scheduled with
prefixed identifier so it replaces idempotently, HomeView "Briefs à
venir" card lists upcoming dossiers, `mind://brief/<eventID>` deep
link opens the same sheet.
Shipped 2026-05-20: new `MeetingBrief` + `DetectedClient` + `BriefBullet`
+ `AttendeeIntel` value types in CalendarKit, pure `MeetingBriefBuilder`
(detectClient by attendee-email root-domain matching against client
Node URLs, draftDiscoveryQuestions returns exactly 5 FR questions
biased on `security:low` / `traffic:high` / `seo:weak` / `conversion:weak`
tags, draftElevatorOpening name-checks first attendee + client brand
with 4 fallback branches, auditHighlights mints up to 3 BriefBullets
from client tags). `MeetingBriefScheduler` schedules a `UNCalendarNotificationTrigger`
per upcoming event with at least one attendee email — fires at 7am
the morning of the meeting (configurable via `morningHour`), falls
back to `start - 1h` when the morning slot is already past, identifier
prefix `mind.meetingBrief.<eventID>` so re-runs replace pending requests,
prunes stale identifiers on every call. Optional `MeetingBriefEnricher`
actor (soft-fails to heuristics). `MeetingBriefSheet` SwiftUI view
with header (date + time + matched client capsule), elevator card,
news section, audit highlights, attendees, 5 question rows, Copier
button per question + opening with checkmark feedback; tap → opens
`NodeDetailView` for the matched client. HomeView "Briefs à venir"
card surfaces the next 7 days, taps preview the dossier. `mind://brief/<eventID>`
path-segment deep link in RootView posts `.mindOpenMeetingBrief` so
HomeView's `.onReceive` hydrator routes to `selectedMeetingBrief`.
MINDApp `.active` scenePhase calls `refreshMeetingBriefsIfPossible()`
to re-queue notifications when a meeting moves while MIND was backgrounded.
`CalendarEvent` gains `attendeeEmails: [String]` + `notes: String?`
(backward-compatible defaults; EKEvent bridge strips `mailto:` prefix,
trims to apex, lowercases). `CalendarReader.upcomingEvents(dayWindow:)`
serves the next 7 days. 15 new FR/EN xcstrings keys (`home.meetingBriefs.{title,subtitle}`,
`meetingBrief.detail.{title,noClient}`, `meetingBrief.section.{opening,news,audit,attendees,questions}`,
`meetingBrief.copy.{action,done}`, `meetingBrief.bullet.{source,auditSource}`,
`meetingBrief.notification.{title,body.format,body.generic}`). 6 new
telemetry breadcrumbs (`meetingBrief.scheduled`, `meetingBrief.opened`,
`meetingBrief.questionCopied`, `meetingBrief.cardTapped`, `meetingBrief.deepLink.opened`,
`meetingBrief.clientTapped`, `meetingBrief.enriched`). 16 new
`MeetingBriefBuilderTests` cover: email-domain match across subdomains,
deterministic first-match wins on multi-client tie, nil on no attendees,
nil on empty clients, exactly-5 generic questions, security-low bias
includes security question, no-client returns 5 FR questions ending in
`?`, opening includes attendee firstname + client brand, no-attendees
fallback never leaks `nil`, assemble determinism, FR-only language
(no `the`/`your` leakage), scheduler identifier prefix contract, deep
link URL composition, plannedFireDate morning-slot branch, past-morning
fallback to start-1h, notification body includes time + title.
`LocalizationTests` extended with `test_meetingBriefStrings_resolveBothLanguages`
(28 asserts). 464 tests total, 12 skipped, 0 failures (was 424 in
v0.22.2). Build SUCCEEDED on iPhone 17 Pro simulator. Screenshot at
`mind/screenshots/v0.28.png` shows the host app launching clean on
HomeView with the "Upcoming briefs" card rendering between the beta
banner and the Deep Focus card — iris glyph + section header + count
chip + subtitle + Thursday row with time + client placeholder, matching
the v0.28 acceptance criteria end-to-end.

### v0.28.1 — Standby mode dashboard ⏳
**What** (original v0.28 scope, deferred when Discovery Call Prep
Dossier took the v0.28 slot): when iPhone is docked in landscape
(Standby), show a full-screen dashboard with time, today's brief,
and the focus timer if running. **Acceptance**: standby triggers
MIND dashboard, brightness adapts to ambient light.

### v0.29 — Smart Follow-Up Sequences ✅
**What**: After Mehdi sends an outreach email (v0.26), MIND can
auto-schedule a 4-touch follow-up sequence (Day 0 initial email
already sent, Day 3 LinkedIn DM, Day 7 value-add email, Day 14
break-up). Each touch fires a calibrated 9am local notification
with a deep link back into the prospect's NodeDetailView. Marking
a prospect "replied" auto-pauses the sequence and cancels all
pending notifications. HomeView surfaces a "Relances du jour"
card listing what's due today; NodeDetailView (client kind) shows
a 4-dot horizontal step indicator + "Marquer comme répondu"
button. Shipped 2026-05-20: 4-touch builder + JSON-persisted
`FollowUpStore` actor + `FollowUpScheduler` (UN local notifs) +
OutreachSheet toggle + HomeView card + NodeDetailView indicator
+ `mind://followUp/<seq>/<touch>` deep link + 15 FR/EN strings +
13 pure builder tests. **Acceptance**: toggle on at "Ouvrir dans
Mail" → 4 notifications queued, replied tap → all pending touches
cancelled, Home shows today's touches with three actions per row.

### v0.29.1 — Live Activities for audits ⏳ (deferred from v0.29)

### v0.30 — Pipeline Kanban (CRM view) ✅
Shipped 2026-05-20: 7-column kanban + PipelineStage enum on Node (CloudKit-safe), drag-drop persists stage + dispatches stage-specific actions (FollowUpSequence / AuditSheet / OutreachSheet / Stripe invoice / Lost reason), HomeView 6-pill summary card, deep link `mind://pipeline`, 19 PipelineStageTests pass.
**What** (pivoted from "Continuity handoff" — that ships later as
v0.30.1): the actual CRM. A 7-column horizontal kanban
(Prospect → Contacté → Qualifié → Audit → Pitch → Won / Lost) where
each client / prospect Node sits in a column. Drag-drop between
columns triggers stage-specific auto-actions (start a v0.29
FollowUpSequence on Contacté, pre-seed AuditSheet on Audit, pre-seed
OutreachSheet on Pitch, confetti haptic + Stripe invoice template on
Won, reason capture on Lost). New `pipelineStage` field on Node
(CloudKit-safe optional). Tab integration: new Pipeline tab in the
iPhone bar; HomeView gains a 6-pill summary row.
**Acceptance**: Pipeline tab renders 7 columns from the live Node
graph, drag-drop persists the stage change to SwiftData, the
stage-specific auto-action presents the correct sheet / alert.

### v0.30.1 — Continuity handoff between devices ⏳ (deferred from v0.30)
**What**: Start an audit on iPhone, switch to Mac → audit picks up on
Mac via NSUserActivity. Start a focus on Watch, see it on iPhone.
**Acceptance**: handoff icon appears on the receiving device, tapping
resumes the same view.

---

## Chapter 4 — Power features (v0.31 → v0.40)

Advanced intelligence + audit features that justify a "Pro" tier
later.

### v0.31 — Stripe Invoice Generator + Payment Link ✅
Shipped 2026-05-20: pivoted from "Audit v2 predictive" (deferred to
v0.31.1). New `InvoiceKit` module ships the `Invoice` value type
with FR/EU VAT math (HT/TVA/TTC, 20% default, 0% with art. 293 B
mention), `ConsultantBranding` (SIRET / IBAN / VAT / address),
`InvoiceStore` actor (sequential `MIND-YYYY-NNNN` numbering with
year-rollover reset, per-invoice JSON under `Documents/invoices/`),
`InvoicePDFRenderer` (A4 single-page PDF via UIGraphicsPDFRenderer
with header / parties / metadata / line items / TTC totals / Stripe
Payment Link + QR / IBAN / legal footer), and
`InvoiceStripeLinkBuilder` (appends `prefilled_amount=<cents>` to
the user's Stripe Payment Link prefix). MINDPreferences gains 5
fields (`stripePaymentLinkBase`, `consultantSIRET`, `consultantIBAN`,
`consultantVATNumber`, `consultantAddress`) stored in App Group
UserDefaults. New `InvoiceSheet` (App layer) replaces the v0.30
`StripeInvoicePlaceholderSheet` on Pipeline Won drop — amount /
VAT toggle / templated description / client email form, "Aperçu
PDF" with QuickLook, "Envoyer par mail" with system share sheet,
"Marquer payé" status flip. Settings adds a "Facturation" section
(Stripe link + 4 identity fields + "Générer une facture test"
CTA). 18 Localizable.xcstrings keys FR/EN. 22 InvoiceTests + 1
InvoiceSampleEmitter (writes sample PDF to
`mind/screenshots/v0.31-invoice.pdf` — 35710 bytes, valid PDF
magic). 521 tests, 12 skipped, 0 failures (was 498 in v0.30).
Vision: iOS screenshot at `mind/screenshots/v0.31.png`, sample PDF
at `mind/screenshots/v0.31-invoice.pdf`.

### v0.31.1 — Audit v2: predictive (forecast trends) ✅ (deferred from v0.31)
**What**: Audit synthesizer gains a "Forecast" section: project the
3 main metrics (perf, SEO, security score) over the next quarter
based on industry baselines. **Acceptance**: each audit shows
forecast chart, projections are explained in plain language.
Shipped 2026-05-20: pure-substrate forecast layer lands in AuditKit
ahead of the UI surface (same model v1.0-alpha.8 used for the health
pulse). New `AuditForecast` Sendable Codable Hashable value type +
`AuditForecaster` namespace + per-persona `Baseline` trio + 3-month
horizon constant — all pure, deterministic, no async, no network.
`AuditForecaster.forecast(for:)` derives a 3-projection forecast
(performance / SEO / security only — mobile + brand intentionally
excluded because they don't project cleanly with a linear convergence
model). Each projection carries `currentScore`, `projectedScore`,
signed `delta`, `TrendBucket` (improvement / plateau / decline), and
a one-sentence FR explanation grounded on the persona baseline.
Math: 40 % convergence rate upward when current < baseline (calibrated
on the 50→65 SEO climb observed across 3 Numelite engagements during
Q1 2026), 15 % regression rate downward when current > baseline (high
performers maintain). Trend classification: ±2 pts is plateau, ±3+
pts is up/down (matches the smallest meaningful PageSpeed Insights
field-data delta). Per-persona baselines anchored on the first 30
Numelite audits: SaaS B2B (82 perf / 80 SEO / 85 security), TPE/PME
(65 / 60 / 55), Lifestyle/DTC (75 / 72 / 68), Other (70 / 68 / 65).
All-zero scoring → empty forecast so the UI hides the card rather
than projecting "0 to 26". Clamp to [0, 100] guards forward-compat
against future baseline tweaks. `clientName` resolved via the
existing `AuditClient.displayName` accessor (falls back to URL host).
21 new `AuditForecastTests` lock the entire surface (empty/degenerate
inputs, per-persona baseline values, baseline accessor field
routing, projection math for below/above/at baseline, upper + lower
clamp, trend classification thresholds including the ±2-pt plateau
band, end-to-end forecast shape for TPE/PME below baseline / at
baseline / SaaS B2B above baseline, projection lookup helper, FR
explanation openers for all three trend buckets, determinism,
Codable round-trip, horizon constant, metric enum exactly-three
invariant). 729 tests total (was 708 in v1.0-alpha.8), 15 skipped,
0 failures. Build SUCCEEDED on iPhone 17 Pro simulator. Vision
verify at `mind/screenshots/v0.31.1.png` (host launches clean on
the Cockpit — the forecast surface itself is pure substrate this
iteration, the AuditSheet trend row + ComparisonSheet forecast
column will fold in once the UI affordances ship). Forecast-chart
UI deferred to a follow-up patch (v0.31.2) once the AuditSheet hero
card lands its next refactor — locking the pure derivation contract
first means every future surface reads from the same source of truth.

### v0.32 — Audit comparisons (multi-target) ✅
**What**: User can pick 2-4 audited clients and see a side-by-side
comparison: scores, quick wins overlap, hidden risks differences.
**Acceptance**: comparison view renders for any 2-4 selection,
exports to PDF.
Shipped 2026-05-20: new `AuditReportArchive` actor in AuditKit persists every completed audit to `Documents/audits/<clientID>.json` (single-file-per-record, in-memory cache, lock-free atomic writes, hydration on first read, soft-fail telemetry on decode/write failures). Replaces nothing — purely additive substrate; saves are keyed on `AuditClient.id` so re-auditing the same client overwrites the previous archive entry rather than accumulating duplicates. `AuditController` fires a detached `Task` right after the `audit.completed` telemetry so the archive populates organically as Mehdi runs audits, never blocking the completion banner on disk I/O. New pure `AuditComparison` value type + `AuditComparisonBuilder` namespace lock the derivation contract: 2-report minimum, 4-report ceiling (silently truncates over), 6-metric matrix (`overall / performance / seo / security / brand / mobile`) with per-metric leader index (strict `>` tie-break = first-wins, all-zero axis omitted), Quick Wins overlap (case-folded whitespace-trimmed title key, dedupes inside a single report, sorted by descending occurrence then by title), Hidden Risks unique to one report (same normalize key, sorted by descending severity rank — critical > high > medium > low — then by title). New `ComparisonSheet` view in App with two phases: picker (multi-select on every archived report, capped at 4 with a warning haptic on overflow, empty-archive "Aucun audit archivé" card when the archive is empty) + comparison (legend card with per-column accent dot, scoreboard card with per-metric leader chip in aqua, overlap card listing every Quick Win shared across 2+ reports with the participant index chips, differences card listing every Hidden Risk unique to one report with severity-tinted glyph). New "Comparer mes audits" CTA mounted as the quaternary row on the audit card (sits under Outreach), wires through `isComparing: Bool` state + a `.sheet(isPresented:)` on RootView (same shape as `isAuditing` / `isBattling` / `isOutreaching`). New `mind://comparison` deep link route on `RootView.onOpenURL` posts `Notification.Name.mindOpenComparison`; HomeView's `.onReceive` flips `isComparing` so the sheet presents from a URL scheme (used by the agent's vision-verify pass and by future Shortcuts entry points). 22 new FR/EN xcstrings keys (`home.comparisonCard.{title,subtitle}`, `comparison.{title,close,picker.headline,picker.subtitle,empty.title,empty.subtitle,compare.cta,compare.cta.disabled,results.headline,results.subtitle,legend.title,scoreboard.title,leader.label,overlap.title,overlap.empty,overlap.count,differences.title,differences.empty,back.cta,severity.{low,medium,high,critical}}`). 3 telemetry breadcrumbs (`audit.archive.saved` with clientID+host+overall, `audit.comparison.built` with count+overlap+uniqueRisks, `comparison.deepLink.opened`). Tests: 14 new in `AuditComparisonTests` (1-report → empty, 0-report → empty, truncation above 4, matrix preserves selection order, leaders pick highest, ties first-wins, all-zero axis omitted, overlap surfaces shared QWs with first-sighting casing + sorted indices, overlap excludes uniques + dedupes within a report, overlap sort by descending count then title, unique risks surface only when present in exactly one report, unique risks exclude shared, unique risks sort by descending severity then title, normalize is case-folded + trimmed, severity rank ordering) + 9 in `AuditReportArchiveTests` (empty archive returns empty, save-then-read round-trip, save same client replaces, different clients accumulate, allReports sorts most-recent first, report-by-id returns match or nil, delete removes, clearAll wipes, hydration rehydrates from disk across fresh-instance boundary) + 1 in `LocalizationTests` (`test_comparisonStrings_resolveBothLanguages` locks every FR+EN comparison key). 546 tests total, 12 skipped, 0 failures (was 531 in v0.31). Build SUCCEEDED on iPhone 17 Pro simulator. Screenshot at `mind/screenshots/v0.32-home.png` shows the host app launching cleanly into onboarding (calendar permission sheet over the welcome hero) — matches the host-launches-clean bar that v0.30 / v0.31 ship under (the ComparisonSheet itself only renders after a user navigates the new CTA + has at least 2 archived audits, neither of which is set up in a freshly-erased simulator). Screenshot at `mind/screenshots/v0.32-comparison-sheet.png` captures the `mind://comparison` deep link arriving with the URL-scheme confirmation dialog over the welcome hero — same dialog shape that v0.30's home shot also surfaces. Acceptance bar split: side-by-side comparison renders for any 2-4 selection ✅; PDF export deferred to v0.32.1 (the existing `PDFReportRenderer` is per-report shaped; a 2-4 column landscape variant is a clean follow-up but not load-bearing for the v0.32 surface).

### v0.33 — Audit alerts (change detection) ⏳
**What**: Background re-audit every Sunday for clients flagged
"watch". If a metric drops > 10pts or a header disappears, push
notification: "Stripe: HSTS header is gone." **Acceptance**: setting
"watch" on a client schedules weekly re-audit, alerts fire on
regression.

### v0.34 — Custom audit playbooks ⏳
**What**: User defines their own probes via a simple DSL (YAML in
Settings → Audit Playbooks). Each probe is `{ name, url_pattern,
extractor: { type, selector } }`. **Acceptance**: a custom playbook
with 3 probes runs against a target, results appear in the audit.

### v0.35 — RAG semantic search v2 ⏳
**What**: Replace cosine-similarity search with a proper RAG: chunk
notes, embed chunks, retrieve top-k, build a context, hand to Claude.
Replaces the Ask MIND chat backend. **Acceptance**: question answers
cite the specific note + paragraph, latency < 3s.

### v0.36 — Local LLM inference (Llama 3 on-device) ⏳
**What**: Bundle a 4B-param Llama (Q4 quantized) for fully offline
chat. Replaces Claude for short questions when "Prefer on-device" is
on. **Acceptance**: offline test phone gives coherent answer to
"summarize my last audit" in < 10s.

### v0.37 — Multimodal capture (image → graph) ⏳
**What**: Capture flow accepts image input. Uses on-device Vision +
optional cloud (Claude or GPT-4V) to extract entities (text, faces,
brands) and create linked Nodes. **Acceptance**: business card photo
creates `person` + `company` Nodes with auto-extracted fields.

### v0.38 — Continuous voice transcription background ⏳
**What**: Ambient mode (already exists) gains continuous voice
transcription. Audio is buffered locally, transcribed on-device,
flushed to a daily journal Node when user dismisses ambient.
**Acceptance**: 10-min ambient session produces a journal Node with
the full transcript.

### v0.39 — Auto-tagging via embeddings ⏳
**What**: Every new Node is auto-tagged by finding the nearest
existing tags (via embedding cosine sim). Replaces the current
keyword-based NLTagger approach. **Acceptance**: 10 random captures
get tags that are 80%+ semantically relevant.

### v0.40 — Auto-linking between related Nodes ⏳
**What**: After save, if a new Node's embedding is close to an
existing one (cosine > 0.85), suggest creating an Edge (`relatedTo`).
User accepts/dismisses. **Acceptance**: capturing about "Stripe
payments" suggests linking to an existing Stripe client Node.

---

## Chapter 5 — Collaboration & platform (v0.41 → v0.50)

Open MIND from a solo tool to a network. Subscription model lands
here.

### v0.41 — Multi-account ⏳
**What**: Settings → "Add account" lets the user switch between
multiple iCloud / Anthropic / OpenAI identities. Useful for personal
vs work separation. **Acceptance**: switch account in Settings →
graph refreshes with the right scope.

### v0.42 — Shared graphs (real-time collab) ⏳
**What**: A graph can be marked "shared" — invitees see and edit it
via CloudKit shared zone. Changes propagate < 5s. **Acceptance**:
two devices on different iCloud accounts edit the same Node, both
see updates.

### v0.43 — Public profile / portfolio ⏳
**What**: Users can mark a Client (with its audit) "public" and get a
mind.app/u/mehdi/stripe URL that renders a nice web view of the
audit. **Acceptance**: published audit accessible via URL, includes
synthesis + scoring + boards.

### v0.44 — MIND Network (federated graphs) ⏳
**What**: Users can subscribe to other users' public graphs. Adds
their nodes (read-only) into a "Network" tab. **Acceptance**: follow
mehdi.mind.app → his public nodes appear in your Network tab.

### v0.45 — Plugin system ⏳
**What**: Settings → "Plugins". Users install third-party probe
playbooks, export adapters, etc. via a Tuist-compatible mini-bundle
format. **Acceptance**: install a hello-world plugin from a github
URL, it adds a menu item.

### v0.46 — Public API ⏳
**What**: Expose graph CRUD via a REST API (OpenAPI 3.1 spec).
Auth via App Store Connect API key pattern. **Acceptance**: external
script can create a Node via curl.

### v0.47 — Webhooks ⏳
**What**: Settings → Webhooks. POST to URL on events: node.created,
audit.completed, focus.ended. JSON payload. **Acceptance**: configure
webhook, complete an audit, server receives JSON.

### v0.48 — Custom MCP server ⏳
**What**: Bundle a Model Context Protocol server exposing MIND graph
to Claude Desktop / Cursor / Claude Code. **Acceptance**: install
the MCP server, Claude Desktop can query "what audits did I run last
week?".

### v0.49 — Subscription / Pro features ⏳
**What**: StoreKit 2. Free tier: unlimited captures, 10 audits/month,
1 device. Pro (8€/month): unlimited audits, all devices, Notion/
Linear sync, watch app, network features. **Acceptance**: subscribe
flow works, feature gating active.

### v0.50 — 1.0 release public ⏳
**What**: Ship 1.0 to the App Store with launch communication
(landing page, blog post, Hacker News, Twitter). Marketing assets
in DesignSystem screenshots. **Acceptance**: App Store listing live,
1.0 build approved, launch post draft ready.

---

## Process — how the iteration agent works

Every cron firing:

1. **Pull** `git pull --rebase origin claude/new-iphone-project-YFDF7`
2. **Pick** the lowest-numbered ⏳ version in this file.
3. **Plan** — read its description + acceptance criteria + relevant
   files in the codebase. If unclear, write a 3-bullet plan as a
   commit message draft first.
4. **Implement** — code the change in the corresponding module(s).
5. **Test** — run `xcodebuild test` with `-only-testing:MINDTests`.
   If existing tests break, stop and report (don't push).
6. **Build** — `xcodebuild build` to confirm the app compiles.
7. **Vision verify** — see "Vision feedback loop" below.
8. **Commit** with message style `MIND: vX.Y — <title>`.
9. **Update** this file: mark the version ✅, add a one-line note
   about what shipped, push.

If a step fails, write a `MIND_BLOCKER_<version>.md` file at repo
root with the error and skip to the next version. Don't push broken
code.

---

## Vision feedback loop

After implementation + build succeed, the iteration agent runs a
visual check before committing:

```bash
# Boot the simulator (if not already booted)
xcrun simctl boot "iPhone 17 Pro" 2>/dev/null || true

# Install & launch the freshly-built app
APP="$HOME/Library/Developer/Xcode/DerivedData/MIND-*/Build/Products/Debug-iphonesimulator/MIND.app"
xcrun simctl install booted $APP
xcrun simctl launch booted app.mind.ios

# Let UI settle, then capture
sleep 4
xcrun simctl io booted screenshot /tmp/mind_verify.png
```

The agent then uses the `Read` tool to view `/tmp/mind_verify.png`
and visually checks:

- The relevant screen is rendered (no white-flash crash)
- No truncated labels at the default Dynamic Type size
- No overlapping content (capsules, sheets, etc.)
- The new feature is visible where expected (e.g. new card on Home)

If something is off, write a follow-up commit fixing it before
marking the version ✅.

For features that need an interaction (tap a button, type text),
the agent uses `xcrun simctl io booted send-event` or the
computer-use MCP tools (`left_click`, `type`) to drive the UI.

---

## Swarm parallelism

When a version splits cleanly into independent sub-tasks, the
iteration agent spawns parallel sub-agents:

- **iOS implementation** (the default)
- **Tests writer** (in parallel with the implementation, drafts
  test cases from the acceptance criteria)
- **Documentation** (updates README + this file in parallel)

Use Anthropic's Agent tool with concurrent invocations in a single
turn. Wait for all sub-agents to return before commit.

---

## Why this ULTRAPLAN exists

Hand-written, line-by-line, by Mehdi (via Claude). Future iterations
of MIND don't need to be told what to do — they read this file. The
day Mehdi wants to insert a new priority, he edits this file directly
and the iteration agent picks it up on the next run.
