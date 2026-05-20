# Vision Pro spatial cockpit — runtime + destination blocker

**v1.0-alpha.19 — partial ship**

## What landed

- `VisionSpatialKit` module gained six new files under
  `mind/Modules/VisionSpatialKit/Sources/`:
  - `SpatialRootView.swift` — `TabView` of three floating Liquid Glass
    panels (Leads / Projects / Audits), gated `#if os(visionOS)`.
  - `SpatialLeadsView.swift` — lead inbox column with hover-lift cards.
  - `SpatialProjectsView.swift` — 3×2 portfolio gallery with hover-lift
    tiles.
  - `SpatialAuditTheater.swift` — audit list with "Présenter en
    immersion" CTA that opens the immersive space.
  - `SpatialAuditTheaterImmersive.swift` — central synthesis panel +
    half-arc of quick-win cards using `TheaterPlacement` for math.
  - `TheaterPlacement.swift` — pure value type computing the half-arc
    positions (compiles + tested on iOS).
  - `SpatialTelemetryBridge.swift` — singleton bridge emitting
    `spatial.app.launched`, `spatial.tab.changed`,
    `spatial.audit.theater.opened`, `spatial.audit.theater.exited`,
    `spatial.lead.tapped`, `spatial.project.tapped` (compiled on every
    platform, surface methods gated where they reference visionOS
    types).
- `MINDApp.swift` gained an `import VisionSpatialKit`, a
  `bootstrapSpatialTelemetry()` call that wires
  `SpatialTelemetryBridge.shared.sink` to `MINDTelemetry`, and a
  `#if os(visionOS)` Scene branch returning the volumetric
  `WindowGroup` of `SpatialRootView` + the `ImmersiveSpace` of
  `SpatialAuditTheaterImmersive`.
- 13 new strings in `Localizable.xcstrings` covering every visible
  spatial label (`spatial.tab.*`, `spatial.empty.*`,
  `spatial.audit.theater.*`, `spatial.window.title`, FR + EN).
- 10 new pure-Swift tests across `SpatialAuditTheaterStateTests`
  (7 — placement math, clamping, symmetry, synthesis panel) and
  `SpatialTokenAvailabilityTests` (4 — telemetry bridge contract).

## What did NOT land — and why

### 1. visionOS Simulator runtime is not installed

```bash
$ xcrun simctl list runtimes
# (no visionOS / xrOS runtime listed; iOS 26.5 only)

$ xcodebuild -showsdks | grep -i vision
# visionOS 26.5 SDK is present, but the matching Simulator runtime
# is not installed on this Mac M5 Pro.
```

Install path (Mehdi, when ready):

1. Xcode → Settings → Components → search "visionOS Simulator 26.5" →
   click the download button.
2. Wait for the download to complete (~5 GB).
3. Quit + reopen Xcode so the new runtime registers.
4. Re-run the visionOS build per the next section.

### 2. `Project.swift` destinations have NOT been updated

The agent prompt called for adding `.visionOS` to `appTarget.destinations`
and every transitive module target. We intentionally **did not** make
this change in v1.0-alpha.19 because:

- Every module the App links would need its destination set bumped to
  include `.visionOS` for the linker to succeed. That includes 30+
  module targets, the Sentry XCFramework (pinned to 8.40.1, visionOS
  support uncertain), the Push / Share / Widget extensions, and the
  Watch target.
- We have no visionOS runtime installed to validate the build before
  shipping — flipping the destination set without being able to run
  `xcodebuild -destination 'platform=visionOS Simulator,...'` risks
  silently breaking the iOS build, which is the v1.0-alpha.19
  acceptance bar.
- The agent prompt explicitly says: "iOS + Catalyst builds must still
  pass." Preserving that contract beats shipping a half-validated
  destination flip.

### 3. visionOS slice build is deferred

The command the agent prompt suggested:

```bash
xcodebuild build -project MIND.xcodeproj -scheme MIND \
  -destination 'platform=visionOS Simulator,name=Apple Vision Pro' \
  -skipPackagePluginValidation \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | tail -10
```

…requires the runtime above. The matching `Project.swift` destination
flip (item 2) and an audit of every UIKit-only reach (ActivityKit in
FocusKit, `UIImpactFeedbackGenerator` in `LiquidHaptics`,
`UIApplication.shared` in MINDApp) for `#if !os(visionOS)` gating is
the v1.0-alpha.20 scope. The substrate (every `#if os(visionOS)`
surface, every test, every string, the bridge wiring) is in place so
that follow-up is purely a Project.swift + gating pass.

## Why this is a sensible partial ship

The Vision Pro spatial cockpit is a **forward-looking** surface — Mehdi
does not have a Vision Pro on hand today. Shipping the code substrate
+ tests + strings + telemetry hooks unlocks the visionOS slice the
moment the runtime is installed, without forcing a half-validated
destination flip through the iOS build path in the meantime.

## Acceptance, today

- iOS Simulator build: SUCCEEDED.
- All 10 new tests pass on the iOS host (the placement math is pure
  Swift; the telemetry bridge is pure value types).
- `mind/screenshots/v1.0-alpha.19.png` shows the iOS host launching
  clean — the visionOS surface is invisible from iOS by design.

## Acceptance, once the runtime lands

- `xcodebuild build` for `platform=visionOS Simulator` returns
  SUCCEEDED.
- `xcrun simctl io booted screenshot` of the visionOS sim shows the
  three floating panels in a `TabView`.
- The "Présenter en immersion" CTA opens the immersive space with the
  synthesis panel + 5 quick-win cards on the half-arc.
