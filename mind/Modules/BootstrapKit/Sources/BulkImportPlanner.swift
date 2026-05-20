import Foundation
import ProjectHealthKit

// v1.0-alpha.11 — Bulk Import GitHub repos.
//
// Pure decision layer that takes a list of `GitHubRepoSummary` rows
// fetched from the GitHub API plus a map of `RepoStackDetection` rows
// (keyed by `fullName`) and buckets them into:
//
//   - `recommendedImports` — Next.js / Shopify / WordPress / static
//     repos with confidence ≥ 0.5. These default to `accepted = true`
//     in the wizard's review step.
//   - `skippedRepos` — every other repo, each carrying a single
//     French sentence explaining why it was skipped. The wizard still
//     renders them so Mehdi can opt back in via "Importer quand même".
//
// The planner is *pure*: no Keychain reads, no SwiftData access, no
// network, no clock. It exists so the wizard's bucketing logic is
// testable without mocking GitHub, and so the same decision tree can
// be re-applied to a "preview" surface without re-fetching.

/// One repo the planner recommends as a candidate import. Carries the
/// derived metadata so the review step can render slug + suggested
/// host + framework badge without re-reading the source rows. The
/// `accepted` toggle defaults to `true`; the wizard's review step
/// flips it on a per-row tap.
public struct PlannedImport: Sendable, Equatable, Identifiable {
    /// Stable identifier so SwiftUI list diffing tracks the row
    /// across re-renders even when the planner is re-invoked with
    /// the same inputs.
    public let id: UUID

    /// Everything the import step needs to mint or update a
    /// `Project` row: slug, name, host, primary color, framework /
    /// confidence detection, and the original repo summary.
    public let metadata: RepoMetadata

    /// Whether this row is checked in the wizard's review step.
    /// Defaults to `true` for every recommended row — Mehdi can
    /// untick individual rows before tapping "Importer N projets".
    public var accepted: Bool

    public init(id: UUID = UUID(), metadata: RepoMetadata, accepted: Bool = true) {
        self.id = id
        self.metadata = metadata
        self.accepted = accepted
    }

    /// Equatable conformance ignores the `accepted` toggle so two
    /// plans built from the same inputs compare equal regardless of
    /// the user's intermediate selection state. Useful for tests
    /// that lock the planner's deterministic output.
    public static func == (lhs: PlannedImport, rhs: PlannedImport) -> Bool {
        return lhs.id == rhs.id
            && lhs.metadata == rhs.metadata
            && lhs.accepted == rhs.accepted
    }
}

/// One repo the planner declined to recommend. Always rendered in
/// the wizard's "Ignorés (vérifie)" section with the `reason`
/// surfaced as the secondary label. A mini-button on the row lets
/// Mehdi import it anyway — bypassing the framework / confidence
/// guard.
public struct SkippedRepo: Sendable, Equatable, Identifiable {
    public let id: UUID

    /// `owner/repo` shape — matches `GitHubRepoSummary.fullName`. The
    /// wizard's "Importer quand même" button looks up the matching
    /// `GitHubRepoSummary` from the original scan output and pushes
    /// it through the per-row metadata path.
    public let fullName: String

    /// One French sentence the wizard renders verbatim under the
    /// row, e.g. `"Framework non supporté (other, confiance 0.32)"`.
    /// Localised strings live in `Localizable.xcstrings` under the
    /// `bulkImport.skipped.reason.*` namespace; the planner emits
    /// the framework + confidence so the caller can format the row
    /// with `String(localized:)`.
    public let reason: String

    public init(id: UUID = UUID(), fullName: String, reason: String) {
        self.id = id
        self.fullName = fullName
        self.reason = reason
    }
}

/// Output of `BulkImportPlanner.plan(repos:detections:)`. Two-bucket
/// shape: recommended (default-on) + skipped (default-off, with
/// reason). The wizard renders each bucket as its own section.
public struct BulkImportPlan: Sendable, Equatable {
    public let recommendedImports: [PlannedImport]
    public let skippedRepos: [SkippedRepo]

    public init(recommendedImports: [PlannedImport], skippedRepos: [SkippedRepo]) {
        self.recommendedImports = recommendedImports
        self.skippedRepos = skippedRepos
    }

    /// Count of recommended rows currently flagged `accepted == true`.
    /// Drives the wizard's CTA label ("Importer N projets") and the
    /// disabled state of the import button when zero.
    public var acceptedCount: Int {
        recommendedImports.filter(\.accepted).count
    }
}

/// Pure decision tree for the bulk import wizard. Reusing `enum`
/// rather than a class so call sites read as
/// `BulkImportPlanner.plan(...)` and there's nothing to instantiate.
public enum BulkImportPlanner {

    /// Frameworks that always end up in the recommended bucket when
    /// the matching detection's confidence clears `confidenceFloor`.
    /// The actual import path can still handle other frameworks — the
    /// gate only governs the default visual recommendation.
    public static let recommendedFrameworks: Set<String> = [
        "nextjs",
        "shopify",
        "wordpress",
        "static",
    ]

    /// Confidence threshold separating recommended from skipped. A
    /// detection with `confidence == 0.5` is a recommendation
    /// (inclusive boundary) so the test that pins the boundary at
    /// 0.5 doesn't drift if the threshold is ever tightened later.
    public static let confidenceFloor: Double = 0.5

    /// Buckets `repos` into a `BulkImportPlan`. `detections` is keyed
    /// by `GitHubRepoSummary.fullName` (`"owner/repo"`). A repo with
    /// no matching detection gets a default `.other` 0-confidence
    /// stub so the planner never throws — soft-fail aligned with
    /// every other v1.0-alpha.* surface.
    ///
    /// Recommendation ordering follows `GitHubRepoSummary.stars`
    /// descending so the most-starred repos float to the top of the
    /// review step. Stable tiebreaker on `fullName` keeps the order
    /// deterministic for the test suite.
    ///
    /// Duplicate input rows (same `fullName`) collapse to the first
    /// occurrence — the second is silently dropped because a Project
    /// row keys on `githubRepo` and re-emitting the same source
    /// twice can't produce two distinct Projects.
    public static func plan(
        repos: [GitHubRepoSummary],
        detections: [String: RepoStackDetection]
    ) -> BulkImportPlan {
        var seenFullNames = Set<String>()
        var deduped: [GitHubRepoSummary] = []
        deduped.reserveCapacity(repos.count)
        for repo in repos {
            if seenFullNames.insert(repo.fullName).inserted {
                deduped.append(repo)
            }
        }

        var recommended: [PlannedImport] = []
        var skipped: [SkippedRepo] = []
        for repo in deduped {
            let detection = detections[repo.fullName] ?? RepoStackDetection(
                framework: "other",
                version: nil,
                confidence: 0.0,
                signals: []
            )
            let metadata = RepoMetadata.derive(repo: repo, detection: detection)
            if recommendedFrameworks.contains(detection.framework)
                && detection.confidence >= confidenceFloor
            {
                recommended.append(PlannedImport(metadata: metadata, accepted: true))
            } else {
                skipped.append(SkippedRepo(
                    fullName: repo.fullName,
                    reason: skipReason(for: detection)
                ))
            }
        }

        recommended.sort { lhs, rhs in
            if lhs.metadata.summary.stars != rhs.metadata.summary.stars {
                return lhs.metadata.summary.stars > rhs.metadata.summary.stars
            }
            return lhs.metadata.summary.fullName < rhs.metadata.summary.fullName
        }

        return BulkImportPlan(
            recommendedImports: recommended,
            skippedRepos: skipped
        )
    }

    /// One-sentence French reason rendered under each skipped row.
    /// Built from the framework + confidence so a glance at the row
    /// tells Mehdi why MIND skipped it. Format mirrors the
    /// `bulkImport.skipped.reason.framework.format` xcstring; we
    /// inline the FR string here so the pure planner stays test-
    /// able without bundling the catalog.
    private static func skipReason(for detection: RepoStackDetection) -> String {
        let confidenceLabel = String(format: "%.2f", detection.confidence)
        return "Framework non supporté (\(detection.framework), confiance \(confidenceLabel))"
    }
}
