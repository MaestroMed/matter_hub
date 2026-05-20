import Foundation

/// v1.0-alpha.10 — Source-code audit findings. The 13 URL probes audit
/// the deployed site (PageSpeed, security headers, TLS, App Store…); a
/// consultant auditing a client's Next.js repo needs the *code* signals
/// too: outdated deps, missing CI, security smells, TypeScript strict
/// on/off, test framework presence, heavy bundle deps.
///
/// Value type all the way down so it crosses the SwiftUI ↔ SwiftData ↔
/// portal-HTML ↔ XCTest boundaries with zero isolation friction. Every
/// field is optional / soft-defaulted because the probe is allowed to
/// soft-fail per signal — a missing `tsconfig.json` doesn't sink the
/// whole audit.
public struct RepositoryAuditFindings: Sendable, Codable, Equatable, Hashable {

    public let analyzedAt: Date

    /// "npm" / "pnpm" / "yarn" / "bun" — inferred from lockfile presence
    /// + the `packageManager` field in `package.json` (Corepack-style).
    public let packageManager: String?

    /// "next@15.0.3" — inferred from `package.json` dependencies. Reads
    /// the first known frontend framework (Next, Remix, Astro, Vite,
    /// Nuxt…) when present, else the first non-trivial dep. Nil when
    /// the package.json couldn't be read.
    public let framework: String?

    /// `compilerOptions.strict === true` in `tsconfig.json`. False when
    /// the file exists but strict is off / missing, false too when
    /// there's no tsconfig at all (the rubric grades that as "no TS").
    public let typescriptStrict: Bool

    /// Total dependency count (deps + devDependencies). 0 when no
    /// package.json could be parsed.
    public let totalDependencies: Int

    /// One entry per dependency that's at least 1 major version behind
    /// the npm registry's `latest` dist-tag. Sorted by `majorBehind`
    /// desc then by name asc so the grade rubric can short-circuit on
    /// the worst offender. Empty when the probe couldn't reach the
    /// registry — soft-fail behaviour, the audit still lands.
    public let outdatedDependencies: [OutdatedDependency]

    /// Heuristic security signals (env files in tree, hardcoded secret
    /// suspects in scanned source, old Node version pinned in
    /// `engines.node`). Sorted by severity desc so the rubric can
    /// short-circuit on the worst signal. Empty when nothing was
    /// flagged or the GitHub tree couldn't be read.
    public let securitySignals: [SecuritySignal]

    /// CI presence (workflows dir + test + deploy classification).
    /// Always present; an empty workflows dir lands as
    /// `hasWorkflows == false`.
    public let ciSignals: CISignals

    /// Tests presence + framework. `hasTestDirectory` is true when any
    /// of `tests/`, `__tests__/`, `e2e/`, `spec/` is present. The
    /// `testFiles` count is an approximation from the GitHub tree (at
    /// most one recursion level deep — full crawl would burn rate
    /// limits) so it's labelled "approximate" in the UI.
    public let testCoverage: TestCoverageSignals

    /// Bundle bloat heuristic — flags deps whose latest published size
    /// (via npm registry) is above the per-dep threshold OR whose
    /// reputation flags them as heavy (moment, lodash, jquery…).
    /// `estimatedKB` is best-effort; nil means the registry didn't
    /// answer.
    public let bundleSignals: BundleSignals

    /// "A+" .. "F" — produced by `RepoAuditGradeBuilder.grade(for:)`.
    /// Stored verbatim so the portal HTML can render the letter as
    /// a 96px CSS centerpiece without re-deriving it.
    public let overallGrade: String

    /// 3-bullet markdown summary produced by
    /// `RepoAuditGradeBuilder.summary(for:)`. The AuditSheet renders
    /// it as a small LiquidCard above the per-signal lists; the
    /// portal HTML wraps it in a `<ul>` directly.
    public let summary: String

    public init(
        analyzedAt: Date = .now,
        packageManager: String? = nil,
        framework: String? = nil,
        typescriptStrict: Bool = false,
        totalDependencies: Int = 0,
        outdatedDependencies: [OutdatedDependency] = [],
        securitySignals: [SecuritySignal] = [],
        ciSignals: CISignals = CISignals(),
        testCoverage: TestCoverageSignals = TestCoverageSignals(),
        bundleSignals: BundleSignals = BundleSignals(),
        overallGrade: String = "F",
        summary: String = ""
    ) {
        self.analyzedAt = analyzedAt
        self.packageManager = packageManager
        self.framework = framework
        self.typescriptStrict = typescriptStrict
        self.totalDependencies = totalDependencies
        self.outdatedDependencies = outdatedDependencies
        self.securitySignals = securitySignals
        self.ciSignals = ciSignals
        self.testCoverage = testCoverage
        self.bundleSignals = bundleSignals
        self.overallGrade = overallGrade
        self.summary = summary
    }
}

/// v1.0-alpha.10 — One dependency that's behind on the npm registry's
/// `latest` dist-tag. `majorBehind` is the integer delta between
/// installed major and latest major (`>= 0`). The grade rubric weights
/// majors heavily because a 2-major-behind dep is a strong
/// "client lets dependencies rot" signal.
public struct OutdatedDependency: Sendable, Codable, Equatable, Hashable {
    public let name: String
    public let installed: String
    public let latest: String
    public let majorBehind: Int

    public init(name: String, installed: String, latest: String, majorBehind: Int) {
        self.name = name
        self.installed = installed
        self.latest = latest
        self.majorBehind = majorBehind
    }
}

/// v1.0-alpha.10 — One security smell. `kind` is a persistence-stable
/// raw string so the AuditSheet UI + the portal HTML can switch on it
/// without crossing an enum boundary that needs a new case for every
/// rubric extension. The current taxonomy:
///
/// - `"hardcoded-secret-suspect"` (`high`) — a regex match against an
///   in-repo source file (typically `.env*` or a config file).
/// - `"env-in-repo"` (`high`) — a `.env` / `.env.local` / `.env.prod`
///   file is committed in the tree.
/// - `"old-node-version"` (`medium`) — `engines.node` is pinned below
///   the current LTS minus one (e.g. `< 18` today).
/// - `"missing-package-lock"` (`low`) — no lockfile found, the repo
///   relies on `package.json` ranges only.
public struct SecuritySignal: Sendable, Codable, Equatable, Hashable {
    public let kind: String
    public let severity: String
    public let detail: String
    public let filePath: String?

    public init(kind: String, severity: String, detail: String, filePath: String? = nil) {
        self.kind = kind
        self.severity = severity
        self.detail = detail
        self.filePath = filePath
    }
}

/// v1.0-alpha.10 — `.github/workflows/*.yml` presence. We classify a
/// workflow as "test" when its filename or contents hit "test" /
/// "ci" / "lint", and as "deploy" when they hit "deploy" / "release" /
/// "vercel" / "publish". A single workflow can satisfy both flags.
public struct CISignals: Sendable, Codable, Equatable, Hashable {
    public let hasWorkflows: Bool
    public let workflowCount: Int
    public let hasTestWorkflow: Bool
    public let hasDeployWorkflow: Bool

    public init(
        hasWorkflows: Bool = false,
        workflowCount: Int = 0,
        hasTestWorkflow: Bool = false,
        hasDeployWorkflow: Bool = false
    ) {
        self.hasWorkflows = hasWorkflows
        self.workflowCount = workflowCount
        self.hasTestWorkflow = hasTestWorkflow
        self.hasDeployWorkflow = hasDeployWorkflow
    }
}

/// v1.0-alpha.10 — Tests presence + best-effort framework inference.
/// `testFramework` reads `"vitest"`, `"jest"`, `"playwright"`,
/// `"cypress"`, `"mocha"`, or nil. The count comes from a recursive
/// listing of `tests/` / `__tests__/` filtered on the conventional
/// extensions — approximation is fine, the UI labels it as such.
public struct TestCoverageSignals: Sendable, Codable, Equatable, Hashable {
    public let hasTestDirectory: Bool
    public let testFiles: Int
    public let testFramework: String?

    public init(
        hasTestDirectory: Bool = false,
        testFiles: Int = 0,
        testFramework: String? = nil
    ) {
        self.hasTestDirectory = hasTestDirectory
        self.testFiles = testFiles
        self.testFramework = testFramework
    }
}

/// v1.0-alpha.10 — Bundle bloat heuristic. `heavyDependencies` lists
/// dep names whose latest tarball size (via npm registry) crossed the
/// threshold, OR whose reputation flagged them as historically heavy.
/// `estimatedKB` is the sum of those sizes when known; nil means the
/// registry couldn't be reached for any of them.
public struct BundleSignals: Sendable, Codable, Equatable, Hashable {
    public let heavyDependencies: [String]
    public let estimatedKB: Int?

    public init(heavyDependencies: [String] = [], estimatedKB: Int? = nil) {
        self.heavyDependencies = heavyDependencies
        self.estimatedKB = estimatedKB
    }
}
