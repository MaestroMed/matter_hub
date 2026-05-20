import Foundation

/// v1.0-alpha.10 — Pure grader. Given a `RepositoryAuditFindings`,
/// returns an "A+" .. "F" letter grade + a 3-bullet markdown summary.
/// Pulled out of the probe so the rubric can be exercised in unit
/// tests without spinning up GitHub Contents calls or the npm
/// registry.
///
/// The rubric is intentionally readable — every grade boundary lives
/// in one short branch, so a future tweak (say, raising the
/// outdated-deps threshold from 5 → 6) lands in one place + the
/// matching test in `RepoAuditGradeBuilderTests`.
public enum RepoAuditGradeBuilder {

    /// Maps signals → letter grade following the v1.0-alpha.10 rubric:
    ///
    /// - **F** : `.env` committed OR hardcoded secret suspect.
    /// - **D** : 2+ high-severity security signals OR no TypeScript.
    /// - **C** : missing CI OR ≥ 6 outdated deps OR 1 high security
    ///   signal.
    /// - **B** : has CI but missing tests OR 3-5 outdated deps with
    ///   ≥ 1 major-behind.
    /// - **A** : 1 minor issue total (e.g. ≤ 2 outdated deps with
    ///   0 major-behind but missing tests, or strict TS off without
    ///   other red flags).
    /// - **A+** : strict TS, ≤ 2 outdated deps with 0 major-behind,
    ///   tests + CI, 0 high security signals.
    ///
    /// Ranked top-down — first match wins. The order makes the worst
    /// cases short-circuit before we can be tricked into giving an A
    /// to a repo with a committed `.env`.
    public static func grade(for findings: RepositoryAuditFindings) -> String {
        // ----- F: catastrophic security signals
        let critical = findings.securitySignals.filter {
            $0.kind == "env-in-repo" || $0.kind == "hardcoded-secret-suspect"
        }
        if !critical.isEmpty {
            return "F"
        }

        // ----- D: multiple high-severity issues OR no TS at all
        let highCount = findings.securitySignals.filter { $0.severity == "high" }.count
        if highCount >= 2 {
            return "D"
        }
        // "No TypeScript" means the framework isn't TS-flavoured AND
        // strict mode is off (no tsconfig). We approximate that with
        // `framework == nil` (we couldn't read package.json) being
        // safe — caller already in worst-case anyway — so we only
        // trip D on an explicit JS framework when strict is off.
        if Self.usesJavaScriptOnly(findings) {
            return "D"
        }

        // ----- C: missing CI OR many outdated deps OR 1 high signal
        let outdatedCount = findings.outdatedDependencies.count
        if !findings.ciSignals.hasWorkflows {
            return "C"
        }
        if outdatedCount >= 6 {
            return "C"
        }
        if highCount == 1 {
            return "C"
        }

        // ----- B: has CI but missing tests OR 3-5 outdated with major
        let majorBehindCount = findings.outdatedDependencies
            .filter { $0.majorBehind >= 1 }.count
        if !findings.testCoverage.hasTestDirectory {
            return "B"
        }
        if outdatedCount >= 3 && majorBehindCount >= 1 {
            return "B"
        }

        // ----- A+ candidates: every soft constraint satisfied
        let cleanSecurity = findings.securitySignals.isEmpty
            || findings.securitySignals.allSatisfy { $0.severity == "low" }
        let hasTests = findings.testCoverage.hasTestDirectory
        let hasCI = findings.ciSignals.hasWorkflows
        let strict = findings.typescriptStrict
        let lightOutdated = outdatedCount <= 2 && majorBehindCount == 0

        if strict && lightOutdated && hasTests && hasCI && cleanSecurity {
            return "A+"
        }

        // ----- A: one minor blemish (strict-off OR 1 low signal OR
        // single non-major outdated). Falls through here because the
        // earlier branches haven't tripped (CI present, tests present,
        // < 3 outdated, no high signals, no .env, etc.).
        return "A"
    }

    /// 3-bullet markdown summary the AuditSheet renders as-is. Bullets:
    /// 1. Framework + package manager + TypeScript flavour.
    /// 2. Dependency hygiene (count + outdated + heavy).
    /// 3. Quality signals (tests, CI, security smells).
    ///
    /// Always 3 bullets so the UI layout stays predictable; missing
    /// information softens into FR copy ("non détecté") rather than
    /// dropping the bullet entirely.
    public static func summary(for findings: RepositoryAuditFindings) -> String {
        let frameworkLine = Self.frameworkBullet(findings)
        let depsLine = Self.depsBullet(findings)
        let qualityLine = Self.qualityBullet(findings)
        return "- \(frameworkLine)\n- \(depsLine)\n- \(qualityLine)"
    }

    // MARK: - Internals

    /// True when we can confidently say there's no TypeScript at all —
    /// strict off + a non-TS framework. A `nil` framework leaves us
    /// agnostic (the probe might not have read package.json), so we
    /// don't pre-emptively trip D.
    private static func usesJavaScriptOnly(_ findings: RepositoryAuditFindings) -> Bool {
        guard !findings.typescriptStrict else { return false }
        guard let framework = findings.framework?.lowercased() else { return false }
        // If the framework string mentions typescript-flavoured tools,
        // we still consider TS present (strict-off only).
        let tsHints = ["typescript", "ts", "next", "remix", "nuxt", "astro"]
        if tsHints.contains(where: { framework.contains($0) }) {
            return false
        }
        return true
    }

    private static func frameworkBullet(_ findings: RepositoryAuditFindings) -> String {
        let framework = findings.framework ?? "framework non détecté"
        let pm = findings.packageManager ?? "package manager inconnu"
        let strictLabel = findings.typescriptStrict
            ? "TypeScript strict"
            : "TypeScript non strict"
        return "\(framework) · \(pm) · \(strictLabel)"
    }

    private static func depsBullet(_ findings: RepositoryAuditFindings) -> String {
        let total = findings.totalDependencies
        let outdated = findings.outdatedDependencies.count
        let majors = findings.outdatedDependencies
            .filter { $0.majorBehind >= 1 }.count
        let heavy = findings.bundleSignals.heavyDependencies.count

        if total == 0 {
            return "Dépendances : non détectées (package.json illisible ou absent)"
        }
        var parts: [String] = ["\(total) dépendances"]
        if outdated == 0 {
            parts.append("aucune en retard")
        } else if majors > 0 {
            parts.append("\(outdated) en retard dont \(majors) majeur(s)")
        } else {
            parts.append("\(outdated) en retard (mineures)")
        }
        if heavy > 0 {
            parts.append("\(heavy) lourdes")
        }
        return parts.joined(separator: ", ")
    }

    private static func qualityBullet(_ findings: RepositoryAuditFindings) -> String {
        let testsLabel: String
        if findings.testCoverage.hasTestDirectory {
            let framework = findings.testCoverage.testFramework ?? "framework de test inconnu"
            testsLabel = "tests présents (\(framework))"
        } else {
            testsLabel = "aucun test détecté"
        }
        let ciLabel: String
        if findings.ciSignals.hasWorkflows {
            ciLabel = "CI active (\(findings.ciSignals.workflowCount) workflows)"
        } else {
            ciLabel = "pas de CI"
        }
        let highCount = findings.securitySignals.filter { $0.severity == "high" }.count
        let secLabel = highCount == 0
            ? "aucun signal de sécurité haut"
            : "\(highCount) signal(s) de sécurité haut"
        return "\(testsLabel) · \(ciLabel) · \(secLabel)"
    }
}
