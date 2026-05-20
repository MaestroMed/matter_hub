# MIND

> **MIND Cockpit Numelite** — the cockpit for a solo studio (Numelite)
> piloting client sites, inbound leads, projects, audits, and invoices
> from one Liquid Glass app. iOS 26 + iPadOS + Mac Catalyst (+ Apple
> Watch + Vision Pro substrate). SwiftUI, SwiftData, CloudKit private
> DB, Tuist 4, Swift 6 strict concurrency.

## Status

**v1.0.0 — TestFlight ready 2026-05-20.** First public release. The
α series (α.1 → α.20) rebuilt the project from second-brain to
Cockpit Studio (lead inbox + audits + projects + invoicing) and
shipped Apple Watch (α.17), ElevenLabs voice clone (α.18), Vision Pro
spatial cockpit substrate (α.19), and Mac Catalyst polish (α.15).

```
13 modules · 30+ features · 1083 tests (24 skipped) · 0 failures
3 destinations green: iOS Simulator, iOS device generic, Mac Catalyst
```

See `mind/AppStore/` for the App Store submission package and
`mind/CHANGELOG.md` for the per-version log.

## Surfaces shipped in 1.0.0

- **Real-time lead inbox** — Cloudflare Worker (`mind/tools/cloudflare-worker`)
  posts to APNs (with a custom Notification Service Extension that
  decorates the alert per-project), routes the tap into `mind://lead/<UUID>`,
  and lands the lead on Home as an enriched card with contact +
  project + AI reply composer.
- **Audit pipeline** — 14 parallel probes (PageSpeed, security
  headers, TLS, DNS, WHOIS, App Store presence, social, sitemap,
  schema, broken links, Lighthouse) synthesised by Claude into an
  `AuditReport` with scoring, quick wins, strategic bets, hidden
  risks, ROI estimate, and a pitch email.
- **Pipeline kanban** — drag-drop columns (lead → discovery → build
  → live → maintenance) backed by `Node.pipelineStage`. Home surfaces
  a summary card; PipelineView is the full board.
- **Client Portal HTML** — every audit one-tap exports a
  single-folder cinematic site (inline CSS + JS + base64 mockups,
  ~26 KB without media, page-weight ceiling locked by tests at
  200 KB). Drop on Vercel / Cloudflare Pages → client URL in 30s.
- **Battle Mode** — radar comparison against competitors, embedded
  into the Client Portal HTML.
- **Generative redesign mockups** — VisualKit calls GPT Image 2
  (`gpt-image-2`) for three brand-aware boards per audit, surfaced
  in AuditSheet + Client Portal.
- **AI Sales Email + Follow-Up Sequences** — OutreachKit composes
  audit-grounded pitches in Mehdi's voice; FollowUpKit schedules a
  3-step sequence with local UN notifications, deep-linked to the
  prospect.
- **Stripe + PDF invoicing** — InvoiceKit ships a Stripe payment
  link builder + a self-contained PDF renderer with sequential
  numbering, SIRET / IBAN graceful skip, FR + EN.
- **Voice clone (ElevenLabs)** — record a 60-180 s WAV with the
  in-app peak-level visualiser, upload to ElevenLabs, then every
  audit pitch synthesises into MP3 in Mehdi's voice. Cached + inlined
  into the Client Portal as a base64 `<audio>` data URL.
- **Lock Screen widgets + Live Activity + Apple Watch** — five
  widget surfaces (rectangular, inline, circular, large StandBy),
  audit Live Activity with Dynamic Island compact + expanded layouts,
  and a 3-tab watchOS app (Leads / Focus / Portfolio) reading the
  shared App Group.
- **Notion + Linear sync** — push an audit page to Notion / a
  quick-win issue to Linear, one tap, token in Keychain.
- **App Shortcuts + Siri** — RunAuditIntent, CaptureIntent,
  AskMINDIntent surfaced in Spotlight + Action Button + Home
  long-press.
- **iPad NavigationSplitView + Mac Catalyst toolbar + Stage Manager**
  — same binary across iPhone, iPad, and Catalyst with native
  navigation + dock-badge live counts.
- **Private CloudKit sync** — every Node lives in the user's private
  CloudKit zone. Nothing on our servers.

## Architecture

```
App                  SwiftUI host (RootView, HomeView, AuditSheet,
 │                   LeadDetailSheet, PipelineView, OnboardingView,
 │                   SettingsView, …).
 │                   - iPhone portrait    → ZStack + LiquidTabBar
 │                   - iPad / Plus regular → NavigationSplitView + sidebar
 │                   - Mac Catalyst       → +.toolbar with MacToolbarAction
 │
 ├─ DesignSystem       Liquid Glass tokens (LiquidCard, LiquidButton,
 │                     LiquidTabBar, LiquidGradient, LiquidPalette,
 │                     LiquidMetrics, LiquidHaptics, RadarChartView,
 │                     ImpactEffortMatrix).
 │
 ├─ GraphCore          SwiftData + CloudKit private DB. Node / Edge /
 │                     Project / Lead / Deliverable / Invoice models,
 │                     SpotlightIndexer, SharedSnapshotWriter (App
 │                     Group columns), WatchConnectivityBridge,
 │                     CockpitWidgetFormatter, WatchKPIFormatter,
 │                     SalesVelocityCalculator, ProjectLifecycleHeuristic,
 │                     MINDTelemetry, MINDPreferences.
 │
 ├─ Intelligence       Anthropic Messages API (cloud), FoundationModels
 │                     on-device summarisation, NaturalLanguage embedding.
 │
 ├─ AuditKit           14-probe orchestrator, ClaudeSynthesizer (parse
 │                     nonisolated for testability), AuditController,
 │                     exporters (PDF / JSON / Markdown), ROIEstimator,
 │                     ClaudeCodeBriefBuilder, ClientPortalKit
 │                     integration.
 │
 ├─ VisualKit          GPT Image 2 client + key store + board composer
 │                     + RedesignMockupGenerator + VisualBoardKey.
 │
 ├─ ClientPortalKit    HTML generator + PortalWriter (atomic write),
 │                     200 KB page-weight ceiling locked by tests.
 │
 ├─ LiveBroadcastKit   Real-time broadcast writer + reader + sample
 │                     HTML for the audit live link.
 │
 ├─ BattleKit          CompetitorLookup + BattleController + BattleReport.
 │
 ├─ OutreachKit        OutreachPromptBuilder + OutreachEmailGenerator +
 │                     mailto URL builder + OutreachSheet.
 │
 ├─ FollowUpKit        FollowUpSequence + FollowUpStore (JSON) +
 │                     FollowUpScheduler (UN notifications) + deep link.
 │
 ├─ InvoiceKit         Invoice value type + InvoicePDFRenderer +
 │                     InvoiceStripeLinkBuilder + InvoiceStore (numbering).
 │
 ├─ NotionKit          NotionTokenStore + NotionPageBuilder + NotionClient.
 │
 ├─ LinearKit          LinearTokenStore + LinearIssueBuilder + LinearClient.
 │
 ├─ VoiceCloneKit      ElevenLabsTokenStore + ElevenLabsClient (voices,
 │                     synthesis), VoiceSampleRecorder + AuditPitchAudioStore.
 │
 ├─ WatchCaptureKit    Watch dictation queue substrate (Codable record,
 │                     transcript assembler, node builder, actor queue).
 │
 ├─ VisionSpatialKit   Vision Pro substrate + immersive AuditTheater
 │                     (gated `#if os(visionOS)`).
 │
 ├─ SwarmKit           SEO swarm prompt builder + zone catalog (>200
 │                     zones) + exporter + on-disk store.
 │
 ├─ ProjectHealthKit   Vercel + GitHub + Lighthouse clients, cache,
 │                     Keychain stores.
 │
 ├─ BootstrapKit       Bulk-import planner + repo summary + template
 │                     library.
 │
 ├─ Settings           MINDPreferences (@Observable), API key fields,
 │                     About + Beta + Danger Zone + iCloud indicator +
 │                     Mac Apparence section + voice-clone section.
 │
 └─ MINDIntents        AppShortcutsProvider — RunAuditIntent +
                       CaptureIntent + AskMINDIntent, surfaced in Siri /
                       Spotlight / Shortcuts / Action Button.

Targets:
- MIND (app, iPhone + iPad + Mac Catalyst)
- MINDWidgets (iOS appExtension)
- MINDShareExtension (iOS appExtension, vCard + URL + text)
- MINDPushService (iOS appExtension, APNs decorator)
- MINDWatch (watchOS 11, single-app layout)
- MINDTests (unit suite, 1083 tests)
```

## Local development

```bash
# Xcode 26.x
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept

brew install tuist xcbeautify gh
gh auth login

git clone https://github.com/MaestroMed/matter_hub.git
cd matter_hub/mind

# Resolve SPM externals (Sentry pinned 8.40.1)
tuist install

# Generate the Xcode project + workspace
tuist generate              # opens MIND.xcworkspace

# Build for the Simulator
xcodebuild \
  -project MIND.xcodeproj \
  -scheme MIND \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -sdk iphonesimulator \
  -skipPackagePluginValidation \
  CODE_SIGNING_ALLOWED=NO build | xcbeautify

# Build for Mac Catalyst
xcodebuild \
  -project MIND.xcodeproj \
  -scheme MIND \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -skipPackagePluginValidation \
  CODE_SIGNING_ALLOWED=NO build | xcbeautify

# Run the full test suite (1083 tests)
xcodebuild test \
  -project MIND.xcodeproj \
  -scheme MIND \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:MINDTests \
  -skipPackagePluginValidation \
  CODE_SIGNING_ALLOWED=NO 2>&1 | xcbeautify
```

## App Store submission

The 1.0.0 submission package lives under `mind/AppStore/`:

- `description.{fr,en}.md` — full App Store description (FR + EN)
- `promotional_text.{fr,en}.md` — 170-char punchline
- `release_notes_1.0.0.{fr,en}.md` — "What's new" copy
- `keywords.{fr,en}.txt` — comma-separated keyword string
- `support_url.txt` / `privacy_url.txt` — required links
- `categories.txt` / `age_rating.txt` / `pricing.txt`
- `fr-FR/` + `en-US/` — `fastlane deliver` directory layout
  (mirrors the top-level Mehdi-facing drafts as one-file-per-key)
- `README.md` — package contents + lane references

Lanes (defined in `mind/fastlane/Fastfile`):

```bash
# Build + upload a TestFlight build
bundle exec fastlane beta

# Sync App Store listing copy (no binary upload)
bundle exec fastlane sync_metadata
```

Required CI env vars: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_CONTENT`,
`MATCH_GIT_URL`, `MATCH_PASSWORD`, `APPLE_ID`, `DEVELOPMENT_TEAM`,
`ITC_TEAM_ID`, optional `TESTFLIGHT_GROUPS`.

The first TestFlight delivery also needs the Apple-side artifacts
documented in the legacy README sections below (App ID, iCloud
container, API key, Match cert repo). See git history for the full
five-step walk-through.

## Privacy

MIND does **not** track users across apps or websites. The privacy
manifest at `App/Resources/PrivacyInfo.xcprivacy` declares:

- `NSPrivacyTracking = false`
- No tracking domains
- Data collected (opt-in / on-device only):
  - Crash Data + Performance Data + Other Diagnostic — Sentry,
    only when the user has saved a DSN
  - Health — on-device only, never leaves the device
  - Audio Data — one-time voice sample, sent to ElevenLabs only when
    the user explicitly taps "Cloner ma voix"
  - Name / Email / Phone — prospect contact info, stays in the
    user's private CloudKit zone; never POSTed anywhere
- Required Reason APIs: UserDefaults (CA92.1), FileTimestamp (C617.1),
  DiskSpace (E174.1), SystemBootTime (35F9.1)

Notes, leads, projects, audits, invoices live in the user's private
CloudKit zone. Nothing leaves the device except the URLs / audit
content / voice sample / outbound mailto the user explicitly submits
to Anthropic / OpenAI / Google PageSpeed / ElevenLabs / their email
client.

## API keys

All stored in the iOS Keychain under separate service identifiers:

| Provider   | Keychain service                | Used by                              |
|------------|---------------------------------|--------------------------------------|
| Anthropic  | `app.mind.ios.anthropic`        | Chat, ClaudeSynthesizer, brief gen   |
| OpenAI     | `app.mind.ios.openai`           | VisualKit (GPT Image 2 boards)       |
| Notion     | `app.mind.ios.notion`           | NotionClient                         |
| Linear     | `app.mind.ios.linear`           | LinearClient                         |
| ElevenLabs | `app.mind.ios.elevenlabs`       | VoiceCloneKit (voice clone + TTS)    |
| Vercel     | `app.mind.ios.vercel`           | ProjectHealthKit                     |
| GitHub     | `app.mind.ios.github`           | ProjectHealthKit                     |
| Sentry     | UserDefaults (DSN only)         | Opt-in crash + perf telemetry        |

Set them inside the app via Settings → the matching section. The voice
clone has its own first-time flow (`VoiceCloneSetupSheet`).

## Roadmap

### 1.x backlog (post-1.0)

- **1.1** — Notion sync bidirectional (read-back the page after a
  manual edit so updates flow back into the Node)
- **1.2** — Discord bot (per-project channel echoing leads + audits +
  invoices)
- **1.3** — Stripe Subscription handling (recurring billing on top of
  the existing one-shot link builder)
- **1.4** — Multi-account support (toggle Numelite / personal /
  client-team scopes via a SceneStorage segmentation)
- **1.5** — Vision Pro runtime install + destinations flip (the
  α.19 substrate is ready; install the visionOS runtime and run the
  immersive theater on real hardware)
- **1.6** — UI Automation snapshots via `fastlane snapshot` to
  publish App Store screenshots per locale × device matrix
- **1.7** — On-device LLM inference (Llama 3 on Foundation Models
  pipeline) for offline audit synthesis
- **1.8** — RAG semantic search v2 over the full lead + audit corpus
- **1.9** — Live Activities for follow-up sequences (next-step
  countdown on the Lock Screen)
- **1.10** — Shared graphs (real-time collab for studio + client)

### 1.0 series (shipped)

See `mind/ULTRAPLAN.md` "Shipped — 1.0 series" section for the full
α.1 → α.20 history. Headline: pivot from second-brain to Cockpit
Studio, 13 modules, Apple Watch + Vision Pro substrate, ElevenLabs
voice clone, Mac Catalyst polish, 1083+ tests.

## Reporting bugs

Two paths, in order of preference:

1. **TestFlight → Send feedback** (built-in). Tap the `Send feedback`
   row in Settings → Beta. iOS routes the tap to the TestFlight
   in-app feedback flow with the screenshot + device info
   auto-attached. The feedback shows up under App Store Connect →
   TestFlight → Feedback, triaged the same day.
2. **GitHub issue** at `MaestroMed/matter_hub` if you want to attach
   a longer repro, link to a CI log, or reference another commit.
   Include the version + build numbers from Settings → About.

Telemetry breadcrumbs flow through `MINDTelemetry` → Sentry on
opt-in builds.

## Project structure

```
mind/
├── App/                  Main app target (RootView, HomeView, sheets, MINDApp)
│   ├── Sources/          SwiftUI files
│   └── Resources/        Assets.xcassets, PrivacyInfo.xcprivacy,
│                          Localizable.xcstrings
├── Modules/              Tuist module targets (one per feature area)
│   ├── DesignSystem/
│   ├── GraphCore/
│   ├── AuditKit/
│   ├── VisualKit/
│   ├── ClientPortalKit/
│   ├── LiveBroadcastKit/
│   ├── BattleKit/
│   ├── OutreachKit/
│   ├── FollowUpKit/
│   ├── InvoiceKit/
│   ├── NotionKit/
│   ├── LinearKit/
│   ├── VoiceCloneKit/
│   ├── WatchCaptureKit/
│   ├── VisionSpatialKit/
│   ├── SwarmKit/
│   ├── ProjectHealthKit/
│   ├── BootstrapKit/
│   ├── Settings/
│   └── MINDIntents/
├── Widgets/              MINDWidgets target (5 widget surfaces)
├── ShareExtension/       MINDShareExtension target (vCard + URL + text)
├── PushExtension/        MINDPushService target (APNs decorator)
├── Watch/                MINDWatch target (watchOS 11 single-app layout)
├── Tests/Sources/        MINDTests (1083 tests)
├── Tuist/                Tuist 4 config + ProjectDescriptionHelpers
├── tools/                Helper scripts (icon generator, Cloudflare worker, …)
├── fastlane/             Appfile, Fastfile (:beta + :sync_metadata), Matchfile
├── AppStore/             App Store submission package (FR + EN)
├── screenshots/          Per-version vision-verify PNGs
├── CHANGELOG.md          Per-version changelog
├── RELEASE_1.0.0.md      Suggested git tag command for the 1.0 release
├── README.md             ← you are here
├── ULTRAPLAN.md          Per-version roadmap (1.x backlog + shipped log)
└── Project.swift         Tuist project manifest
```

## Phases (legacy)

The phases below were the pre-pivot scaffolding. They are kept here
because the iteration agent still references them in commit
messages. The current iteration model is the `v1.0-alpha.x` ladder
(see ULTRAPLAN.md) capped by this 1.0.0 release.

- Phase 0 – 11 ✅ Scaffold → modules → Watch → Vision Pro substrate
- Phase 7 ⏳ First TestFlight delivery (Mehdi runs the lane)
- Phase 8 ⏳ Verify iCloud sync between both iPhones once on TestFlight
- Phase ∞ ⏳ Vision Pro runtime install + immersive theater on device
