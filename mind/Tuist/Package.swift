// swift-tools-version: 5.9
@preconcurrency import PackageDescription

let package = Package(
    name: "MIND",
    dependencies: [
        // Pinned just under 8.45 — that version introduced a separate
        // `SentryCppHelper` binary target which Tuist 4 fails to embed
        // automatically. 8.40.x is the last release before the split
        // and ships every feature we need for crash + perf reporting.
        .package(url: "https://github.com/getsentry/sentry-cocoa", exact: "8.40.1"),
    ]
)
