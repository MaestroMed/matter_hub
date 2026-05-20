# MIND 1.0.0 — Release notes (for Mehdi)

Shipped 2026-05-20. Cockpit Numelite. TestFlight ready.

## Suggested git tag

When you're ready to cut the release (after the first TestFlight
delivery lands and you've signed off the listing copy in App Store
Connect), tag the commit:

```bash
cd /Users/mehdinafaa/Developer/matter_hub
git tag -a v1.0.0 -m "MIND 1.0.0 — Cockpit Numelite"
git push origin v1.0.0
```

The `v1.0.0` tag also acts as the canonical reference for the GitHub
release page (auto-created by `gh release create v1.0.0 --generate-notes`
if you want a one-liner).

## TestFlight delivery

```bash
cd /Users/mehdinafaa/Developer/matter_hub/mind
bundle install
bundle exec fastlane beta
```

The lane:

1. Regenerates the Xcode project via Tuist.
2. Pulls signing certs from Match (for the host app + 4 embedded
   extensions: widgets, share, push, watchkitapp).
3. Bumps `CFBundleVersion` from the previous TestFlight build
   number + 1 (App Store Connect is the source of truth).
4. Archives the `Release` configuration via `gym`.
5. Uploads to App Store Connect via `pilot`, with the FR release
   notes pulled straight from `mind/AppStore/release_notes_1.0.0.fr.md`
   as the TestFlight changelog.
6. Optionally distributes to TestFlight groups when
   `TESTFLIGHT_GROUPS` is set (comma-separated).

Required env (CI or local):
`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_CONTENT`,
`MATCH_GIT_URL`, `MATCH_PASSWORD`, `APPLE_ID`, `DEVELOPMENT_TEAM`,
`ITC_TEAM_ID`.

## App Store listing copy sync

The listing copy lives under `mind/AppStore/`. To push it without
shipping a new binary:

```bash
bundle exec fastlane sync_metadata
```

This uploads the description / promotional text / keywords /
release notes / categories / age rating from the `fr-FR/` + `en-US/`
subfolders to App Store Connect. Run any time the listing copy
changes; the lane skips screenshots until `mind/AppStore/screenshots/`
gets populated (future v1.6 chore via `fastlane snapshot`).

## Verification artifacts

- `mind/screenshots/v1.0.0.png` — iOS host on iPhone 17 Pro Simulator
  at 1.0.0, showing the lead inbox (4 leads: Sarah Ben, Marc Petit,
  Lucie Aubry, Pierre Loi) + KPI bar (4 leads / 5 actifs / 0 builds /
  0 erreurs / 830 €/mo) + Vélocité card + tab bar.
- `mind/CHANGELOG.md` — per-version log capped at 1.0.
- `mind/ULTRAPLAN.md` — full α.1 → α.20 + 1.0.0 history + 1.x
  backlog.
- 3 destinations BUILD SUCCEEDED (iOS Sim Debug, iOS device generic
  Release with signing disabled, Mac Catalyst Debug).
- Test suite green at 1083 tests, 24 skipped, 0 failures.

## What still needs Mehdi-side action

1. **Apple Developer Program** — active membership (already done).
2. **App ID `app.mind.ios` + iCloud Container `iCloud.app.mind.ios`**
   — created in developer.apple.com (already done for the α
   TestFlight uploads).
3. **App Store Connect listing** — create the app entry under
   App Store Connect → My Apps → +, bundle ID `app.mind.ios`. The
   `sync_metadata` lane is what fills in the listing copy
   afterwards.
4. **Push Notifications certificate / key** — register an APNs key
   under developer.apple.com → Keys → +. The `MINDPushService`
   extension is signed via Match, but APNs delivery requires the
   key set on the App ID (Capabilities → Push Notifications).
5. **First `bundle exec fastlane beta` run** — produces the
   v1.0.0 build, uploads to TestFlight. Apple processes it ~10
   minutes, the build appears in TestFlight and propagates to
   testers.
6. **Submit for App Store review** — once you've validated the
   TestFlight build, hit "Submit for Review" in App Store Connect.
   Apple reviews ~24-48 h, then 1.0.0 hits the public store.

The git tag is the last step: cut `v1.0.0` once the App Store
listing is live so the tag lines up with the published release.
