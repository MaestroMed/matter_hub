# MIND v0.22.1 blocker — Watch voice capture

## Why blocked

v0.22.1 requires Apple-side artifacts the agent cannot mint:

1. **watchOS App target**: a brand-new `MIND Watch App` extension
   must be added to `Project.swift` and the workspace. Tuist can
   declare it, but the resulting target needs a bundle identifier
   under the same provisioning team as `app.mind.ios`. Without a
   provisioning profile that includes the watch app identifier the
   simulator install path still works, but `xcrun simctl` watch
   simulators must be paired with an iPhone simulator and that
   pairing isn't deterministic from the agent's headless context.

2. **CloudKit container**: voice-captured nodes must round-trip from
   the watch to the iPhone. That requires the `iCloud.app.mind.ios`
   CloudKit container, the `com.apple.developer.icloud-container-identifiers`
   entitlement, and a `CKContainer` schema that includes the
   `Node` record type. None of those exist today.

3. **SFSpeech entitlement on watchOS**: speech recognition on
   watchOS requires `NSSpeechRecognitionUsageDescription` in the
   Watch app's Info.plist AND audio session category negotiation
   with the paired phone. Achievable but the simulator path is
   flaky.

## What Mehdi needs to do

- Create the iCloud container `iCloud.app.mind.ios` in
  developer.apple.com.
- Add a provisioning profile that includes the watch app identifier
  `app.mind.ios.watchkitapp`.
- Decide if v0.22.1 should ship as a "pretend" Watch app that just
  records to the local sandbox (no CloudKit, no pairing) so the UX
  can be prototyped without the entitlement dance.

## What the agent did instead

Skipped v0.22.1 and shipped v0.22.2 (Direct WebSocket broadcasting)
in this iteration. v0.22.1 stays `⏳`.
