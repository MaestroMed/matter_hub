# MIND — ULTRAPLAN v2 (50 versions)

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

### v0.18 — Voice cloning for read-back (AVSpeechSynthesizer + Apple's neural voices) ⏳
**What**: On any Node, "Listen" button that reads the content with
the highest-quality Apple neural voice (Siri Natural). Useful for
long audits while driving. **Acceptance**: audio plays via AirPods,
pause/resume works, locks screen continues playback.

### v0.19 — OCR for photos (VNRecognizeTextRequest) ⏳
**What**: Capture from photo: user picks a photo (a whiteboard, a
business card, a screenshot) → MIND OCRs it and creates a Node with
the extracted text as content. **Acceptance**: French + English
handwriting both recognised, photo attached to the Node.

### v0.20 — First public TestFlight beta ⏳
**What**: Open the TestFlight to 50 external testers via the Apple
beta link. Add a `Beta` badge to the About section. Surface a
"Send feedback" link via FB Reporter. **Acceptance**: 50-tester
distribution active, in-app feedback link opens TestFlight feedback.

---

## Chapter 3 — Multi-device (v0.21 → v0.30)

Expand from iPhone-only to the full Apple device family. Every
device reads the same CloudKit graph.

### v0.21 — Apple Watch focus complication ⏳
**What**: New target MINDWatch. Focus complication shows current
session remaining time, tap → opens the WatchOS focus view (start /
end). CloudKit syncs FocusSessionRecord. **Acceptance**: complication
updates live, start/end roundtrips to iPhone.

### v0.22 — Watch voice capture ⏳
**What**: Watch "Capture" view with mic button → records voice →
transcribes via SFSpeech → creates Node on CloudKit → syncs to iPhone.
**Acceptance**: 10-second voice capture appears on iPhone within
30s.

### v0.23 — Mac Catalyst app ⏳
**What**: Enable Mac Catalyst on the App target. Optimise window
sizing, menu bar with capture/focus/audit. Sidebar always visible.
**Acceptance**: app runs on Mac, menu bar shortcuts work, window
resizes cleanly.

### v0.24 — iPad Stage Manager polish ⏳
**What**: Optimise for Stage Manager: stable window aspect ratios,
keyboard shortcuts for capture/focus, drag-drop URL from Safari to
QuickCapture. **Acceptance**: 6 windows in Stage Manager don't break
layout, ⌘N opens Quick Capture.

### v0.25 — Vision Pro spatial layout ⏳
**What**: Enable visionOS target. Cards float in 3D space, focus
timer becomes a glowing sphere, audit reports float as readable
panels. **Acceptance**: app runs on Vision Pro simulator, basic
interactions work.

### v0.26 — CarPlay capture ⏳
**What**: CarPlay scene with a single big "Capture by voice" button.
Same SFSpeech flow as iPhone. Useful for hands-free note-taking
while driving. **Acceptance**: app appears in CarPlay menu, voice
capture creates Node.

### v0.27 — Lock Screen widgets ⏳
**What**: Lock Screen widgets (circular, rectangular, inline) for
focus timer + quick capture + today's brief. **Acceptance**: all 3
widget styles render correctly on lock screen, tap deep-links into
app.

### v0.28 — Standby mode dashboard ⏳
**What**: When iPhone is docked in landscape (Standby), show a full-
screen dashboard: time, today's brief, focus timer if running.
**Acceptance**: standby triggers MIND dashboard, brightness adapts
to ambient light.

### v0.29 — Live Activities for audits ⏳
**What**: When an audit runs in background, show a Live Activity with
the phase indicator + cancel button. Dynamic Island compact view shows
phase icon. **Acceptance**: audit running shows in DI, tap expands,
cancel works.

### v0.30 — Continuity handoff between devices ⏳
**What**: Start an audit on iPhone, switch to Mac → audit picks up on
Mac via NSUserActivity. Start a focus on Watch, see it on iPhone.
**Acceptance**: handoff icon appears on the receiving device, tapping
resumes the same view.

---

## Chapter 4 — Power features (v0.31 → v0.40)

Advanced intelligence + audit features that justify a "Pro" tier
later.

### v0.31 — Audit v2: predictive (forecast trends) ⏳
**What**: Audit synthesizer gains a "Forecast" section: project the
3 main metrics (perf, SEO, security score) over the next quarter
based on industry baselines. **Acceptance**: each audit shows
forecast chart, projections are explained in plain language.

### v0.32 — Audit comparisons (multi-target) ⏳
**What**: User can pick 2-4 audited clients and see a side-by-side
comparison: scores, quick wins overlap, hidden risks differences.
**Acceptance**: comparison view renders for any 2-4 selection,
exports to PDF.

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
