# MIND

A second-brain iOS app built around a single typed graph. Liquid Glass UI,
on-device Apple Intelligence (Foundation Models), Claude API for heavy
reasoning. iOS 26+, SwiftUI, SwiftData, CloudKit, Tuist 4.

## Status

Phase 0 (scaffold) and the first big push are done: every planned module is
linked, the app boots with a working 4-tab navigation, on-device summarization
is wired to `LanguageModelSession`, and cloud reasoning is wired to the
Anthropic Messages API. Next milestones are Widgets / Live Activities
(Phase 6) and TestFlight (Phase 7) — see "Roadmap" below.

## Architecture

```
App                  SwiftUI shell, Liquid Glass surfaces, LiquidTabBar nav
 │                   (Home / Notes / + / Chat / Settings)
 │
 ├─ DesignSystem     Liquid Glass tokens + components
 │                   (LiquidBackground, LiquidCard, LiquidButton,
 │                    LiquidTabBar, LiquidToggle, LiquidSlider,
 │                    LiquidSearchField, LiquidPill)
 │
 ├─ GraphCore        Universal Object Graph (SwiftData + CloudKit private DB
 │                   with local fallback when iCloud entitlements are not
 │                   signed, e.g. unsigned Simulators). Node + Edge models.
 │
 ├─ Intelligence     On-device summarization via FoundationModels
 │                   (LanguageModelSession), NaturalLanguage for tagging,
 │                   Anthropic Messages API for cloud, Keychain for the key.
 │
 ├─ Notes            First feature surface: SwiftData @Query, search, tags.
 ├─ Chat             "Ask MIND" — cloud chat with graph context injection.
 ├─ Capture          QuickCaptureSheet + voice (SFSpeech on-device).
 ├─ Settings         API key + on-device toggle + Claude model picker.
 └─ MINDIntents      AppShortcutsProvider — CaptureIntent + AskMindIntent,
                     surfaced in Siri, Spotlight, Shortcuts, Action Button.
                     (Local module name is MINDIntents to avoid collision
                     with the Apple framework `AppIntents`.)
```

Everything is a `Node` in a single typed graph. Modules are just views and
intents on top of that graph. Adding a new module never touches the data
layer.

## Local development

Requirements on macOS (M1 or newer recommended):

```bash
# Xcode 26.x from the Mac App Store
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept

# Tooling
brew install tuist xcbeautify gh
gh auth login

# Repo
git clone https://github.com/MaestroMed/matter_hub.git
cd matter_hub/mind
tuist generate     # opens MIND.xcworkspace in Xcode

# Or build + run from CLI (the path the CI uses, mirrors the workflow exactly)
xcodebuild \
  -project MIND.xcodeproj \
  -scheme MIND \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -sdk iphonesimulator \
  CODE_SIGNING_ALLOWED=NO build | xcbeautify

# Launch in a booted Simulator
xcrun simctl install booted ~/Library/Developer/Xcode/DerivedData/MIND-*/Build/Products/Debug-iphonesimulator/MIND.app
xcrun simctl launch  booted app.mind.ios
```

## Deploying to TestFlight

The pipeline is wired (see `.github/workflows/ios.yml` and `fastlane/Fastfile`)
but cannot run until the Apple-side artifacts exist. Do the five Apple steps
first, then drop the secrets into GitHub.

### 1. Apple Developer Program

Active membership on https://developer.apple.com/account.
The active account must have **App Manager** or higher role in the team that
owns `app.mind.ios`.

### 2. App ID + iCloud Container

On https://developer.apple.com/account/resources:

- **Identifiers → App IDs → +** : create `app.mind.ios`.
  - Description: `MIND`
  - Bundle ID: Explicit, `app.mind.ios`
  - Capabilities: enable **iCloud** and **Push Notifications** (CloudKit
    needs both), plus **Background Modes** (Audio + Background processing
    are already declared in `MIND-Info.plist`).
- **Identifiers → iCloud Containers → +** : create `iCloud.app.mind.ios`.
- Back on the App ID, edit iCloud → **Edit** → tick the new container.

The container ID must match exactly the one in
`GraphCore/Sources/GraphContainer.swift` (`cloudKitDatabase:
.private("iCloud.app.mind.ios")`) and in `App/MIND.entitlements`.

### 3. App Store Connect listing

On https://appstoreconnect.apple.com:

- **My Apps → +** : create a new iOS app.
  - Name: `MIND`
  - Bundle ID: `app.mind.ios` (picks up the App ID from step 2)
  - SKU: `MIND` (anything unique)
  - Primary language: French or English — your call
- Note the **App Store Connect Team ID** (it shows under the app's URL
  parameters once created). This is `ITC_TEAM_ID` in the secrets list below.

### 4. App Store Connect API key

On https://appstoreconnect.apple.com/access/integrations/api:

- **Generate API Key** with **App Manager** role.
- Download the `.p8` file — you get exactly one chance.
- Note the **Key ID** (10 chars) and the **Issuer ID** (UUID at the top).

These become `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_CONTENT`.

### 5. Match certificate repo

`fastlane match` stores signing certificates in an encrypted git repo so CI
can resign builds without a Mac.

- Create a **private** repo, e.g. `MaestroMed/mind-certificates`.
- Generate a fine-grained GitHub PAT with read+write on that repo only.
- `MATCH_GIT_URL` is `https://x:<TOKEN>@github.com/MaestroMed/mind-certificates`.
- `MATCH_PASSWORD` is any long passphrase you pick — used to encrypt the
  contents of the repo. Save it in your password manager.

The first `match appstore` run has to happen on a Mac with the Apple ID
logged into Xcode (Settings → Accounts). After that CI can read from the
repo on every build.

```bash
cd matter_hub/mind
bundle install
bundle exec fastlane match appstore   # creates the certs, pushes them encrypted
```

### 6. GitHub Secrets

Repo → **Settings → Secrets and variables → Actions → New repository secret**.

| Secret              | Value                                                         |
|---------------------|---------------------------------------------------------------|
| `APPLE_ID`          | Your Apple ID email (the developer account)                   |
| `DEVELOPMENT_TEAM`  | 10-char Team ID from developer.apple.com / membership page    |
| `ITC_TEAM_ID`       | Numeric App Store Connect team ID (step 3)                    |
| `MATCH_GIT_URL`     | `https://x:<TOKEN>@github.com/MaestroMed/mind-certificates`   |
| `MATCH_PASSWORD`    | The passphrase you used with `match` in step 5                |
| `ASC_KEY_ID`        | 10-char API key ID (step 4)                                   |
| `ASC_ISSUER_ID`     | UUID issuer ID (step 4)                                       |
| `ASC_KEY_CONTENT`   | Full `.p8` contents incl. `-----BEGIN PRIVATE KEY-----` lines |

### 7. First TestFlight build

Once all secrets are in place:

- GitHub → **Actions → MIND iOS → Run workflow**
- Set `deploy = true`, branch `claude/new-iphone-project-YFDF7` (or `main`)
- Wait ~8–12 min: build → archive → match → upload → ASC processing
- Open TestFlight on your iPhone Air / iPhone 14 Pro Max → new build appears
  within a few minutes of the upload completing

## Claude API key

Stored in iOS Keychain under service `app.mind.ios.anthropic`. Set it inside
the app on first run via the Settings tab → "Anthropic API Key". The cloud
model picker (Sonnet 4.6 / Opus 4.7 / Haiku 4.5) lives right below.

## Roadmap

- **Phase 0** ✅ CI pipeline + scaffold (App + DesignSystem + GraphCore + Notes)
- **Phase 1** ✅ All modules linked (Intelligence, Settings, Chat, Capture, MINDIntents)
- **Phase 2** ✅ Deployment target bumped to iOS 26
- **Phase 3** ✅ Foundation Models on-device summarization
- **Phase 4** ✅ `LiquidTabBar` with Home / Notes / + / Chat / Settings
- **Phase 5** ✅ MINDIntents surfaced for Siri / Spotlight / Action Button
- **Phase 6** ⏳ Widgets + Live Activities + Dynamic Island (Widget Extension target)
- **Phase 7** ⏳ First TestFlight build on iPhone Air + iPhone 14 Pro Max — see above
- **Phase 8** ⏳ Verify iCloud sync between both iPhones
- **Phase 9** ⏳ Tasks module + Focus Timer (live focus session card)
- **Phase 10** ⏳ Ambient mode for the docked iPhone 14 Pro Max (always-on dashboard + continuous voice capture)
- **Phase 11** ⏳ Modules: Health (HealthKit), Habits, Journal, Finance, Reading, Contacts, Goals, Travel, Smart Home (HomeKit)
- **Phase ∞** ⏳ Apple Watch + Mac + Vision Pro clients reading the same CloudKit graph
