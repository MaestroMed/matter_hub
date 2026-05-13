# MIND

A second-brain iOS app with Liquid Glass UI, on-device Apple Intelligence, and
Claude API for heavy reasoning.

> Status: Phase 0 scaffold. Builds on CI macOS runners → ships to TestFlight on your iPhone.

## Architecture

```
App  (SwiftUI shell, Liquid Glass surfaces)
 │
 ├─ DesignSystem    Liquid Glass tokens + components (LiquidBackground, LiquidCard, LiquidButton, LiquidTabBar)
 ├─ GraphCore       Universal Object Graph (SwiftData + CloudKit) — Node + Edge model
 ├─ Intelligence    On-device (Foundation Models) + Cloud (Claude API) + Keychain key store
 ├─ Capture         Quick capture sheet (voice via SFSpeech, text, photo TBD)
 └─ Notes           First feature surface on top of the graph
```

Every "thing" in MIND is a `Node` in a single typed graph. Modules are just
views and intents on top of that graph. Adding a new module never touches the
data layer.

## Local development (requires macOS)

You don't need this if you're developing entirely via CI from iPhone.

```bash
brew install mise
mise install
bundle install
tuist install && tuist generate
open MIND.xcodeproj
```

## Deploying to TestFlight (zero Mac required)

### One-time setup

1. **Apple Developer Program** — https://developer.apple.com/programs/enroll
2. **App Store Connect** — create a new app:
   - Bundle ID: `com.mind.app` (change in `Project.swift`, `fastlane/Appfile`, `App/MIND.entitlements`, `Modules/GraphCore/Sources/GraphContainer.swift`)
   - SKU: `MIND`
   - Platform: iOS
3. **Match repo** — create a private GitHub repo for fastlane signing certificates (e.g. `mind-certificates`).
4. **App Store Connect API key** — create one at
   https://appstoreconnect.apple.com/access/api with Admin role.
   Download the `.p8` file.
5. **GitHub Secrets** — in this repo Settings → Secrets and variables → Actions, add:

   | Secret              | Value                                         |
   |---------------------|-----------------------------------------------|
   | `APPLE_ID`          | Your Apple ID email                           |
   | `DEVELOPMENT_TEAM`  | 10-char Team ID from developer.apple.com      |
   | `ITC_TEAM_ID`       | App Store Connect team ID (numeric)           |
   | `MATCH_GIT_URL`     | `https://x:<TOKEN>@github.com/you/mind-certs` |
   | `MATCH_PASSWORD`    | Passphrase for the encrypted match repo       |
   | `ASC_KEY_ID`        | API key ID (10 chars)                         |
   | `ASC_ISSUER_ID`     | API issuer UUID                               |
   | `ASC_KEY_CONTENT`   | Full `.p8` file contents (paste as-is)        |

6. **First match run** (must run once on a Mac to seed the certs repo):
   ```bash
   bundle exec fastlane match appstore
   ```
   Or skip this and let the CI create certs on first run via `match` with
   `readonly: false` temporarily.

### Pushing a build

Every push to a `claude/**` branch builds the app on macOS runners.
To ship a build to TestFlight:

1. Go to GitHub → Actions → "MIND iOS"
2. Run workflow → set `deploy = true`
3. Wait ~8–12 min
4. Open TestFlight on iPhone → new build appears

## Claude API key

Stored locally in iOS Keychain (`com.mind.app.anthropic`). Set it on first run
through Settings inside the app.

## Roadmap

- Phase 0 ✅ Scaffold, design system, graph schema, capture sheet, notes view
- Phase 1 Embeddings + semantic search across the graph
- Phase 2 Tasks, Focus timer, Live Activities, Dynamic Island
- Phase 3 Ambient mode for the secondary iPhone (docked dashboard + always-listen)
- Phase 4 Modules: Health, Habits, Journal, Finance, Reading, Contacts, Goals…
- Phase 5 App Intents everywhere → Siri / Spotlight / Shortcuts
- Phase 6 Apple Watch, Mac, Vision Pro clients (same graph)
