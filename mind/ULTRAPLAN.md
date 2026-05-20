# MIND — ULTRAPLAN v2 (50 versions)

> ⚠️ **MIND a pivoté (2026-05-20).** Le projet n'est plus un second-
> brain : c'est désormais un **cockpit Studio** pour l'agence Numelite
> — outil interne pour piloter sites clients, leads, projets et
> factures. Voir `v1.0-alpha.*` pour le nouveau scope. Les entrées du
> chapitre 3+ ci-dessous sont **préservées pour archéologie** ; la
> roadmap réelle vit désormais dans les versions `v1.0-alpha.x`.

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

### v0.22.1 — Watch voice capture ⏳
**What**: Watch "Capture" view with mic button → records voice →
transcribes via SFSpeech → creates Node on CloudKit → syncs to iPhone.
**Acceptance**: 10-second voice capture appears on iPhone within
30s.

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

### v0.25.1 — Vision Pro spatial layout ⏳
**What** (original v0.25 scope, deferred when ROI Calculator took
the slot 2026-05-19): Enable visionOS target. Cards float in 3D
space, focus timer becomes a glowing sphere, audit reports float
as readable panels. **Acceptance**: app runs on Vision Pro
simulator, basic interactions work.

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

### v0.27.1 — Lock Screen widgets ⏳
**What**: Lock Screen widgets (circular, rectangular, inline) for
focus timer + quick capture + today's brief. **Acceptance**: all 3
widget styles render correctly on lock screen, tap deep-links into
app. (Deferred from v0.27 to make room for the Lead Scoring Engine
pivot — the score is the load-bearing "who do I call next" signal
that the Lock Screen widgets will eventually surface anyway.)

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

### v0.31.1 — Audit v2: predictive (forecast trends) ⏳ (deferred from v0.31)
**What**: Audit synthesizer gains a "Forecast" section: project the
3 main metrics (perf, SEO, security score) over the next quarter
based on industry baselines. **Acceptance**: each audit shows
forecast chart, projections are explained in plain language.

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
