import Foundation

/// v1.2.0 — Bidirectional Notion sync. Pure planner that turns
/// `(NotionDatabase, sampleRows)` into a default `NotionImportMapping`
/// — the wizard surfaces this in step 2 and Mehdi can override it
/// before the executor runs.
///
/// Why pure?
/// ---------
/// The mapping decision is heuristic + visible to the user, so it
/// has to be testable from `MINDTests` without any network round-trip
/// and without a NotionClient instance. Every assertion in
/// `NotionImportPlannerTests` exercises the heuristic directly.

/// Where this NotionDatabase should land inside MIND's data spine.
public enum TargetKind: String, Sendable, Codable, CaseIterable, Equatable {
    case project
    case lead
    case deliverable
    case audit
    case ignored
}

/// Auto-detected mapping: which MIND entity this Notion database
/// becomes, which Notion property maps to the title, which (optional)
/// property maps to the body, and how confident the detection is.
public struct NotionImportMapping: Sendable, Codable, Equatable {
    public let targetNodeKind: TargetKind
    public let titlePropertyName: String
    public let bodyPropertyName: String?
    public let confidence: Double
    public let detectedFields: [String: String]

    public init(
        targetNodeKind: TargetKind,
        titlePropertyName: String,
        bodyPropertyName: String?,
        confidence: Double,
        detectedFields: [String: String]
    ) {
        self.targetNodeKind = targetNodeKind
        self.titlePropertyName = titlePropertyName
        self.bodyPropertyName = bodyPropertyName
        self.confidence = confidence
        self.detectedFields = detectedFields
    }
}

/// Pure heuristic planner. Single static method per the spec —
/// stateless, deterministic, no I/O.
public enum NotionImportPlanner {

    /// Inspects the database title + property names + a sample of
    /// rows and returns the best-guess mapping. Confidence reflects
    /// how strong the title match is and whether sample rows were
    /// available to corroborate.
    public static func suggestMapping(
        database: NotionDatabase,
        sampleRows: [NotionPage]
    ) -> NotionImportMapping {
        let kind = detectKind(databaseTitle: database.title)
        let titleProp = detectTitleProperty(in: database.propertyNames, sampleRows: sampleRows)
        let bodyProp = detectBodyProperty(in: database.propertyNames)
        let confidence = computeConfidence(
            kind: kind,
            sampleRowCount: sampleRows.count,
            titlePropFound: !titleProp.isEmpty
        )
        let detected = detectExtraFields(in: database.propertyNames, for: kind)
        return NotionImportMapping(
            targetNodeKind: kind,
            titlePropertyName: titleProp,
            bodyPropertyName: bodyProp,
            confidence: confidence,
            detectedFields: detected
        )
    }

    // MARK: - Heuristics

    /// Title-keyword match. Order matters: "audit" wins before
    /// "lead" so "Audit leads 2026" still routes to `.audit`.
    static func detectKind(databaseTitle title: String) -> TargetKind {
        let lower = title.lowercased()
        if lower.contains("audit") { return .audit }
        if lower.contains("client") || lower.contains("project") || lower.contains("projet") {
            return .project
        }
        if lower.contains("lead") || lower.contains("prospect") {
            return .lead
        }
        if lower.contains("task") || lower.contains("tache") || lower.contains("tâche")
            || lower.contains("deliverable") || lower.contains("livrable") {
            return .deliverable
        }
        return .ignored
    }

    /// FR + EN heuristic. Default Notion title column is "Name";
    /// FR workspaces default to "Nom". If neither appears, fall
    /// back to the first property alphabetically.
    static func detectTitleProperty(
        in propertyNames: [String],
        sampleRows: [NotionPage]
    ) -> String {
        let preferred = ["Name", "Nom", "Title", "Titre"]
        for candidate in preferred where propertyNames.contains(candidate) {
            return candidate
        }
        return propertyNames.first ?? "Name"
    }

    /// Looks for the canonical body / notes property. FR variants
    /// first because that's our MIND user.
    static func detectBodyProperty(in propertyNames: [String]) -> String? {
        let preferred = ["Description", "Notes", "Note", "Content", "Contenu", "Body", "Corps", "Message"]
        for candidate in preferred where propertyNames.contains(candidate) {
            return candidate
        }
        return nil
    }

    /// Confidence formula:
    /// - .ignored → 0.30 (we're guessing the user wanted to skip)
    /// - kind + sample rows + title prop hit → 0.95
    /// - kind + sample rows, title missing → 0.75
    /// - kind detected, no sample rows → 0.60
    /// - kind detected, title prop missing, no sample → 0.40
    static func computeConfidence(
        kind: TargetKind,
        sampleRowCount: Int,
        titlePropFound: Bool
    ) -> Double {
        if kind == .ignored { return 0.30 }
        switch (sampleRowCount > 0, titlePropFound) {
        case (true,  true):  return 0.95
        case (true,  false): return 0.75
        case (false, true):  return 0.60
        case (false, false): return 0.40
        }
    }

    /// Surface "we noticed this column" hints. Pure inspection.
    static func detectExtraFields(
        in propertyNames: [String],
        for kind: TargetKind
    ) -> [String: String] {
        var hints: [String: String] = [:]
        if propertyNames.contains("Status") || propertyNames.contains("Statut") {
            hints["status"] = "detected"
        }
        if propertyNames.contains("Email") {
            hints["email"] = "detected"
        }
        if propertyNames.contains("URL") || propertyNames.contains("Website") || propertyNames.contains("Site") {
            hints["url"] = "detected"
        }
        if propertyNames.contains("Owner") || propertyNames.contains("Assigned") || propertyNames.contains("Responsable") {
            hints["owner"] = "detected"
        }
        return hints
    }
}
