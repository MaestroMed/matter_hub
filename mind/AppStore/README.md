# MIND — App Store submission package

Drafted 2026-05-20 for the v1.0.0 TestFlight + App Store submission.

## Layout

Two parallel layouts coexist in this folder so the package is readable
both by a human reviewer and by `fastlane deliver` (the `sync_metadata`
lane wired in `mind/fastlane/Fastfile`):

- **Top-level `*.fr.md` / `*.en.md`** — Mehdi-facing drafts. Easier
  to skim, edit, and version-control. The `release_notes_<version>.fr.md`
  file is also read by the `:beta` lane to upload the TestFlight
  changelog.
- **`fr-FR/` and `en-US/` subfolders** — `fastlane deliver` convention.
  Plain `.txt` files (no markdown), one per metadata key, organized
  per locale. Plus the global `copyright.txt`, `primary_category.txt`,
  `secondary_category.txt`. These are the files Fastlane uploads
  verbatim to App Store Connect.

Keep both layouts in sync when editing.

## Asset references

- `support_url.txt` → `https://numelite.fr/support`
- `privacy_url.txt` → `https://numelite.fr/privacy`
- `marketing_url.txt` → `https://numelite.fr`
- `categories.txt` → Primary: Productivity, Secondary: Business
- `age_rating.txt` → 4+
- `pricing.txt` → Free (planned IAPs later)

## Screenshots

Not in this folder yet. Capture via:

```bash
fastlane snapshot
```

Snapshots land under `fr-FR/screenshots/` + `en-US/screenshots/`
per Apple's screen-size matrix (6.7" iPhone, 6.1" iPhone, 12.9" iPad,
13" iPad, macOS Mac Catalyst).

For v1.0.0 the host screenshot at `mind/screenshots/v1.0.0.png` is
the manual smoke test; UI Automation snapshots are a v1.1+ chore.

## Lanes

```bash
# Build + upload to TestFlight (single command)
bundle exec fastlane beta

# Re-sync App Store listing copy without uploading a new build
bundle exec fastlane sync_metadata
```

Both lanes need these env vars in CI:
`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_CONTENT`,
`MATCH_GIT_URL`, `MATCH_PASSWORD`, `APPLE_ID`, `DEVELOPMENT_TEAM`,
`ITC_TEAM_ID`, and optionally `TESTFLIGHT_GROUPS=Numelite Internal,...`.
