import Foundation
import GraphCore
import ProjectHealthKit

/// v1.0-alpha.10 — Repository-aware audit probe. The 13 URL probes
/// audit the deployed site; this 14th probe audits the **code** behind
/// it. Reads via the GitHub Contents API + recursive tree:
///
/// - `package.json` → framework, package manager, deps, total count
/// - `tsconfig.json` → strict mode
/// - `.github/workflows/` listing → CI presence + classification
/// - `tests/` / `__tests__/` heuristics → coverage signal
/// - `.env*` files in tree → security risk
/// - npm registry → outdated dep detection + heavy dep size
///
/// Soft-fails per signal: a missing tsconfig leaves `typescriptStrict
/// = false` and the probe still lands. Concurrent fan-out via
/// `async let` so the package.json read can race the recursive tree
/// listing — they're independent calls.
public actor RepositoryAuditProbe {

    public static let shared = RepositoryAuditProbe()

    /// Maximum number of dependencies we'll fan-out npm-registry
    /// requests for. The full package.json can pull in 200+ deps,
    /// and we don't want to burn npm's rate limit on every audit.
    /// 25 is enough to catch the "client lets dependencies rot"
    /// signal — if the top 25 deps are clean, the long tail
    /// probably is too.
    static let maxRegistryFanOut: Int = 25

    /// Dependencies the industry has flagged as historically heavy.
    /// Any of these in package.json triggers a `BundleSignals.heavyDependencies`
    /// entry even when the npm registry doesn't return a size.
    static let knownHeavyDeps: Set<String> = [
        "moment", "lodash", "jquery", "rxjs",
        "@material-ui/core", "@mui/material",
        "firebase", "aws-sdk", "@aws-sdk/client-s3",
    ]

    /// Per-dep size threshold above which we flag the dep as heavy.
    /// 500 KB unpacked is roughly where a modern frontend dep starts
    /// to bite into the JS bundle even with treeshaking.
    static let heavyDepSizeThresholdKB: Int = 500

    /// Run the full repo audit. Returns a `RepositoryAuditFindings`
    /// with whatever signals could be collected — never throws to
    /// the caller. Soft-fails preserve information; the grade builder
    /// reads the final shape.
    public func run(
        repo: String,
        github: GitHubClient = .shared,
        npmRegistry: NpmRegistryClient = .shared,
        now: Date = .now
    ) async -> RepositoryAuditFindings {
        await Self.telemetryInfo("repoAudit.started", data: ["repo": repo])

        async let packageJSONString = github.readFile(repo: repo, path: "package.json")
        async let tsConfigString = github.readFile(repo: repo, path: "tsconfig.json")
        async let workflowsListing = github.listDirectory(repo: repo, path: ".github/workflows")
        async let tree = Self.fetchTree(github: github, repo: repo)

        let packageJSON = await packageJSONString
        let tsConfig = await tsConfigString
        let workflows = await workflowsListing
        let treeEntries = await tree

        // Pure parsers (no I/O). All return soft defaults on bad
        // input so a malformed package.json doesn't sink the run.
        let packageInfo = Self.parsePackageJSON(packageJSON)
        let strict = Self.detectTypescriptStrict(tsConfig)
        let ciSignals = Self.classifyWorkflows(workflows)
        let testCoverage = Self.classifyTests(
            packageJSON: packageInfo,
            tree: treeEntries
        )
        let securitySignals = Self.detectSecuritySignals(
            tree: treeEntries,
            packageInfo: packageInfo
        )

        // Outdated + heavy deps require live npm registry calls. We
        // race up to `maxRegistryFanOut` lookups in a TaskGroup so a
        // single slow dep doesn't gate the whole probe.
        let topDependencies = Array(
            packageInfo.dependencies
                .sorted { $0.name < $1.name }
                .prefix(Self.maxRegistryFanOut)
        )
        let (outdated, heavyDepSizes) = await Self.fetchRegistrySignals(
            dependencies: topDependencies,
            registry: npmRegistry
        )
        let bundleSignals = Self.bundleSignals(
            packageInfo: packageInfo,
            heavySizes: heavyDepSizes
        )

        // Seed findings with everything we collected, then ask the
        // grade builder for the letter + summary so the snapshot is
        // self-contained.
        var seed = RepositoryAuditFindings(
            analyzedAt: now,
            packageManager: packageInfo.packageManager,
            framework: packageInfo.framework,
            typescriptStrict: strict,
            totalDependencies: packageInfo.totalDependencyCount,
            outdatedDependencies: outdated,
            securitySignals: securitySignals,
            ciSignals: ciSignals,
            testCoverage: testCoverage,
            bundleSignals: bundleSignals,
            overallGrade: "F",
            summary: ""
        )
        let grade = RepoAuditGradeBuilder.grade(for: seed)
        let summary = RepoAuditGradeBuilder.summary(for: seed)
        seed = RepositoryAuditFindings(
            analyzedAt: seed.analyzedAt,
            packageManager: seed.packageManager,
            framework: seed.framework,
            typescriptStrict: seed.typescriptStrict,
            totalDependencies: seed.totalDependencies,
            outdatedDependencies: seed.outdatedDependencies,
            securitySignals: seed.securitySignals,
            ciSignals: seed.ciSignals,
            testCoverage: seed.testCoverage,
            bundleSignals: seed.bundleSignals,
            overallGrade: grade,
            summary: summary
        )

        await Self.telemetryInfo(
            "repoAudit.completed",
            data: [
                "repo": repo,
                "grade": grade,
                "outdated": "\(outdated.count)",
                "security": "\(securitySignals.count)",
            ]
        )
        await Self.telemetryInfo(
            "repoAudit.outdated.count",
            data: ["repo": repo, "count": "\(outdated.count)"]
        )
        await Self.telemetryInfo(
            "repoAudit.security.signals.count",
            data: ["repo": repo, "count": "\(securitySignals.count)"]
        )
        return seed
    }

    /// Bridge to the `@MainActor`-isolated `MINDTelemetry` facade. The
    /// probe lives in a non-MainActor actor (the audit fan-out runs
    /// off-main), so direct calls would trip the actor-isolation
    /// boundary. Hops to main, fires the breadcrumb, returns.
    static func telemetryInfo(
        _ name: String,
        data: [String: String]
    ) async {
        await MainActor.run {
            MINDTelemetry.info(name, data: data)
        }
    }

    // MARK: - Tree fetch with main/master fallback

    /// Tries `main`, falls back to `master`. The actor on the other
    /// side soft-fails on 404 so we can attempt both branches without
    /// throwing.
    static func fetchTree(github: GitHubClient, repo: String) async -> [GitHubTreeEntry] {
        let mainTree = await github.recursiveTree(repo: repo, branch: "main")
        if !mainTree.isEmpty { return mainTree }
        return await github.recursiveTree(repo: repo, branch: "master")
    }

    // MARK: - Pure parsers (testable in isolation)

    /// Parsed slice of `package.json`. Only the fields the audit
    /// signal cares about — full schema parsing would be overkill.
    public struct PackageInfo: Sendable, Equatable {
        public let framework: String?       // "next@15.0.3"
        public let packageManager: String?  // "pnpm" / "npm" / …
        public let nodeEngine: String?      // "engines.node" raw range
        public let dependencies: [PackageDependency]
        public let devDependencies: [PackageDependency]

        public var totalDependencyCount: Int {
            dependencies.count + devDependencies.count
        }

        public init(
            framework: String? = nil,
            packageManager: String? = nil,
            nodeEngine: String? = nil,
            dependencies: [PackageDependency] = [],
            devDependencies: [PackageDependency] = []
        ) {
            self.framework = framework
            self.packageManager = packageManager
            self.nodeEngine = nodeEngine
            self.dependencies = dependencies
            self.devDependencies = devDependencies
        }
    }

    public struct PackageDependency: Sendable, Equatable {
        public let name: String
        public let range: String

        public init(name: String, range: String) {
            self.name = name
            self.range = range
        }
    }

    /// Parses the slim subset we read from package.json. Returns
    /// soft defaults on a malformed payload — the rest of the probe
    /// degrades gracefully.
    public static func parsePackageJSON(_ raw: String?) -> PackageInfo {
        guard let raw = raw,
              let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return PackageInfo()
        }
        let deps = Self.flattenDeps(json["dependencies"])
        let devDeps = Self.flattenDeps(json["devDependencies"])
        // package manager: explicit `packageManager` field (Corepack-style)
        // or a lockfile hint that gets folded in via tree scan elsewhere.
        let packageManager: String? = {
            if let pm = json["packageManager"] as? String,
               let separator = pm.firstIndex(of: "@") {
                return String(pm[pm.startIndex..<separator])
            }
            return nil
        }()
        // node engine
        let nodeEngine: String? = {
            if let engines = json["engines"] as? [String: Any],
               let node = engines["node"] as? String {
                return node
            }
            return nil
        }()
        // Framework inference: walk deps for known frontend frameworks
        // in priority order, fall back to first non-trivial dep.
        let framework = Self.inferFramework(deps: deps, devDeps: devDeps)
        return PackageInfo(
            framework: framework,
            packageManager: packageManager,
            nodeEngine: nodeEngine,
            dependencies: deps,
            devDependencies: devDeps
        )
    }

    static func flattenDeps(_ raw: Any?) -> [PackageDependency] {
        guard let dict = raw as? [String: Any] else { return [] }
        return dict.compactMap { (key, value) in
            guard let stringValue = value as? String else { return nil }
            return PackageDependency(name: key, range: stringValue)
        }.sorted { $0.name < $1.name }
    }

    static func inferFramework(
        deps: [PackageDependency],
        devDeps: [PackageDependency]
    ) -> String? {
        let prioritised = [
            "next", "remix", "@remix-run/react",
            "astro", "nuxt", "vite",
            "react", "vue", "@angular/core", "svelte", "solid-js",
        ]
        let all = deps + devDeps
        for name in prioritised {
            if let match = all.first(where: { $0.name == name }) {
                let version = Self.cleanVersionString(match.range)
                return "\(name)@\(version)"
            }
        }
        return nil
    }

    /// Strips leading `^` / `~` / `>=` / `=` so the framework label
    /// reads as "next@15.0.3" not "next@^15.0.3".
    static func cleanVersionString(_ range: String) -> String {
        let trimmed = range.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = trimmed
        let prefixes = ["^", "~", ">=", "<=", "=", ">", "<"]
        for prefix in prefixes {
            if result.hasPrefix(prefix) {
                result = String(result.dropFirst(prefix.count))
            }
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Detects `compilerOptions.strict === true` in a tsconfig.json
    /// payload. False on bad input / absence — the rubric reads
    /// "strict off" + JS framework as the "no TypeScript" branch.
    public static func detectTypescriptStrict(_ raw: String?) -> Bool {
        guard let raw = raw,
              let data = raw.data(using: .utf8) else {
            return false
        }
        // tsconfig is JSON with comments (JSONC). The strip is rough
        // but adequate — we only need `compilerOptions.strict`.
        let stripped = Self.stripJSONCComments(raw)
        guard let stripData = stripped.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: stripData) as? [String: Any]
        else {
            // Fall back to the raw data without strip — sometimes
            // jsonc is valid JSON.
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let compilerOptions = json["compilerOptions"] as? [String: Any] {
                return (compilerOptions["strict"] as? Bool) == true
            }
            return false
        }
        guard let compilerOptions = json["compilerOptions"] as? [String: Any] else {
            return false
        }
        return (compilerOptions["strict"] as? Bool) == true
    }

    /// Removes `//` and `/* */` style comments from a JSONC blob.
    /// Imperfect (doesn't handle strings containing `//`) but good
    /// enough for tsconfig.json which rarely embeds those.
    static func stripJSONCComments(_ input: String) -> String {
        var result = ""
        var lines = input.split(separator: "\n", omittingEmptySubsequences: false)
        for index in lines.indices {
            var line = String(lines[index])
            if let slashIdx = line.range(of: "//") {
                line = String(line[line.startIndex..<slashIdx.lowerBound])
            }
            lines[index] = Substring(line)
        }
        result = lines.joined(separator: "\n")
        // Block comment strip (single-pass, non-nested).
        while let openRange = result.range(of: "/*"),
              let closeRange = result.range(
                of: "*/",
                range: openRange.upperBound..<result.endIndex
              )
        {
            result.removeSubrange(openRange.lowerBound..<closeRange.upperBound)
        }
        return result
    }

    /// Classifies the shallow `.github/workflows/` listing. We
    /// detect "test" / "deploy" workflows from their filename keywords
    /// — readFile-per-workflow would be too expensive.
    public static func classifyWorkflows(_ entries: [GitHubContentEntry]) -> CISignals {
        let files = entries.filter {
            $0.type == "file"
                && ($0.name.hasSuffix(".yml") || $0.name.hasSuffix(".yaml"))
        }
        guard !files.isEmpty else {
            return CISignals(
                hasWorkflows: false,
                workflowCount: 0,
                hasTestWorkflow: false,
                hasDeployWorkflow: false
            )
        }
        let lowercaseNames = files.map { $0.name.lowercased() }
        let testKeywords = ["test", "ci", "lint", "check"]
        let deployKeywords = ["deploy", "release", "vercel", "publish"]
        let hasTest = lowercaseNames.contains { name in
            testKeywords.contains { name.contains($0) }
        }
        let hasDeploy = lowercaseNames.contains { name in
            deployKeywords.contains { name.contains($0) }
        }
        return CISignals(
            hasWorkflows: true,
            workflowCount: files.count,
            hasTestWorkflow: hasTest,
            hasDeployWorkflow: hasDeploy
        )
    }

    /// Detects the testing framework + counts approximate test files.
    /// Framework inference picks the first match from the canonical
    /// ranking; count comes from the tree filter on `*.test.*` /
    /// `*.spec.*` paths.
    public static func classifyTests(
        packageJSON: PackageInfo,
        tree: [GitHubTreeEntry]
    ) -> TestCoverageSignals {
        let allDeps = packageJSON.dependencies + packageJSON.devDependencies
        let depNames = Set(allDeps.map { $0.name })
        // Priority order: explicit test runners first.
        let frameworkCandidates = [
            "vitest", "jest", "playwright", "cypress",
            "mocha", "ava", "tape", "uvu",
        ]
        let detected = frameworkCandidates.first(where: depNames.contains)

        let testDirs = ["tests/", "__tests__/", "e2e/", "spec/"]
        let hasTestDirectory = tree.contains { entry in
            testDirs.contains { entry.path.lowercased().hasPrefix($0) }
        } || tree.contains { entry in
            let lc = entry.path.lowercased()
            return lc.contains(".test.") || lc.contains(".spec.")
        }
        let testFileCount = tree.reduce(0) { acc, entry in
            let lc = entry.path.lowercased()
            let inDir = testDirs.contains { lc.hasPrefix($0) }
            let suffixHit = lc.contains(".test.") || lc.contains(".spec.")
            return acc + ((inDir || suffixHit) && entry.type == "blob" ? 1 : 0)
        }
        return TestCoverageSignals(
            hasTestDirectory: hasTestDirectory,
            testFiles: testFileCount,
            testFramework: detected
        )
    }

    /// Surfaces security signals from the tree + package info:
    /// committed .env files, old Node engines, missing lockfile. The
    /// hardcoded-secret-suspect signal lives in a separate code path
    /// (would require reading actual file bodies, expensive) and
    /// surfaces only when a .env file content scan trips a regex.
    public static func detectSecuritySignals(
        tree: [GitHubTreeEntry],
        packageInfo: PackageInfo
    ) -> [SecuritySignal] {
        var signals: [SecuritySignal] = []
        // .env files at any depth → high-severity
        for entry in tree where entry.type == "blob" {
            let lc = entry.path.lowercased()
            let name = lc.split(separator: "/").last.map(String.init) ?? lc
            // Skip the canonical safe sample files.
            if name == ".env.example" || name == ".env.sample" || name == ".env.template" {
                continue
            }
            if name == ".env"
                || name.hasPrefix(".env.")
            {
                signals.append(
                    SecuritySignal(
                        kind: "env-in-repo",
                        severity: "high",
                        detail: "Fichier d'environnement committé : \(entry.path)",
                        filePath: entry.path
                    )
                )
            }
        }
        // engines.node below LTS-1 → medium
        if let engine = packageInfo.nodeEngine {
            if Self.isNodeEngineStale(engine) {
                signals.append(
                    SecuritySignal(
                        kind: "old-node-version",
                        severity: "medium",
                        detail: "engines.node pinned à une version obsolète : \(engine)",
                        filePath: "package.json"
                    )
                )
            }
        }
        // No lockfile → low
        let lockfileMarkers: Set<String> = [
            "package-lock.json", "yarn.lock", "pnpm-lock.yaml", "bun.lockb",
        ]
        let hasLock = tree.contains { entry in
            let name = entry.path.lowercased().split(separator: "/").last.map(String.init) ?? ""
            return lockfileMarkers.contains(name)
        }
        if !hasLock && packageInfo.totalDependencyCount > 0 {
            signals.append(
                SecuritySignal(
                    kind: "missing-package-lock",
                    severity: "low",
                    detail: "Aucun fichier de verrouillage détecté : versions des dépendances flottantes.",
                    filePath: nil
                )
            )
        }
        return signals
    }

    /// True when the `engines.node` constraint pins us below Node 18
    /// (the v1.0-alpha.10 LTS minus one). Very conservative heuristic
    /// — strips the leading operator and reads the first integer.
    public static func isNodeEngineStale(_ engine: String) -> Bool {
        let trimmed = engine
            .replacingOccurrences(of: ">=", with: "")
            .replacingOccurrences(of: "^", with: "")
            .replacingOccurrences(of: "~", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let firstSegment = trimmed.split(separator: ".").first.map(String.init) ?? trimmed
        let digitsOnly = firstSegment.filter(\.isNumber)
        guard let major = Int(digitsOnly) else { return false }
        return major < 18
    }

    /// Fans out npm registry calls in a TaskGroup, splits the
    /// results into:
    ///  - outdated deps (latest major > installed major)
    ///  - heavy deps by size + known-heavy reputation list
    static func fetchRegistrySignals(
        dependencies: [PackageDependency],
        registry: NpmRegistryClient
    ) async -> (outdated: [OutdatedDependency], heavy: [String: Int]) {
        var heavy: [String: Int] = [:]
        var outdated: [OutdatedDependency] = []

        await withTaskGroup(of: (PackageDependency, NpmRegistryClient.NpmPackageInfo?).self) { group in
            for dep in dependencies {
                group.addTask {
                    do {
                        let info = try await registry.latest(packageName: dep.name)
                        return (dep, info)
                    } catch {
                        return (dep, nil)
                    }
                }
            }
            for await (dep, infoOptional) in group {
                guard let info = infoOptional else { continue }
                if let size = info.approximateSizeKB,
                   size >= Self.heavyDepSizeThresholdKB {
                    heavy[dep.name] = size
                }
                let installedMajor = majorVersion(of: dep.range)
                let latestMajor = majorVersion(of: info.version)
                guard let installedMajor, let latestMajor else { continue }
                if latestMajor > installedMajor {
                    outdated.append(
                        OutdatedDependency(
                            name: dep.name,
                            installed: dep.range,
                            latest: info.version,
                            majorBehind: latestMajor - installedMajor
                        )
                    )
                } else if info.version != normaliseVersion(dep.range)
                    && latestMajor == installedMajor
                    && minorOrPatchAhead(latest: info.version, installed: dep.range) {
                    outdated.append(
                        OutdatedDependency(
                            name: dep.name,
                            installed: dep.range,
                            latest: info.version,
                            majorBehind: 0
                        )
                    )
                }
            }
        }
        outdated.sort {
            if $0.majorBehind != $1.majorBehind {
                return $0.majorBehind > $1.majorBehind
            }
            return $0.name < $1.name
        }
        return (outdated, heavy)
    }

    /// Returns the leading integer of a semver-ish string. "^15.2.0"
    /// → 15. nil when nothing parsable shows up.
    public static func majorVersion(of raw: String) -> Int? {
        let cleaned = cleanVersionString(raw)
        let firstSegment = cleaned.split(separator: ".").first.map(String.init) ?? cleaned
        let digitsOnly = firstSegment.filter(\.isNumber)
        return Int(digitsOnly)
    }

    /// True when the latest version is strictly ahead of installed in
    /// minor or patch, sharing the same major. Conservative — only
    /// trips when both versions parse cleanly.
    static func minorOrPatchAhead(latest: String, installed: String) -> Bool {
        let latestParts = latest.split(separator: ".")
        let installedParts = cleanVersionString(installed).split(separator: ".")
        guard latestParts.count >= 2, installedParts.count >= 2,
              let latestMinor = Int(latestParts[1]),
              let installedMinor = Int(installedParts[1])
        else { return false }
        if latestMinor > installedMinor { return true }
        if latestParts.count >= 3 && installedParts.count >= 3,
           let latestPatch = Int(latestParts[2]),
           let installedPatch = Int(installedParts[2]),
           latestPatch > installedPatch {
            return true
        }
        return false
    }

    /// Removes the leading semver operator. Pulled out for sort
    /// stability when comparing to npm registry `latest`.
    static func normaliseVersion(_ raw: String) -> String {
        cleanVersionString(raw)
    }

    /// Folds the registry + reputation signals into the
    /// `BundleSignals` shape. `heavySizes` is the per-dep KB sum
    /// from the registry fan-out; reputation hits get added with
    /// nil size so the heavy list is still surfaced even when the
    /// registry didn't return a size for that dep.
    static func bundleSignals(
        packageInfo: PackageInfo,
        heavySizes: [String: Int]
    ) -> BundleSignals {
        var heavy = Set(heavySizes.keys)
        let depNames = Set(packageInfo.dependencies.map { $0.name })
        for reputation in Self.knownHeavyDeps where depNames.contains(reputation) {
            heavy.insert(reputation)
        }
        let sorted = heavy.sorted()
        let totalKB: Int? = heavySizes.isEmpty
            ? nil
            : heavySizes.values.reduce(0, +)
        return BundleSignals(
            heavyDependencies: sorted,
            estimatedKB: totalKB
        )
    }
}
