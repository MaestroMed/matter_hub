import Foundation
import Observation
import AuditKit
import GraphCore

/// Drives a full board generation: ask Claude for N prompts per category,
/// pipe each prompt through OpenAI gpt-image-2, persist the PNG and the
/// manifest to the App Group filesystem, and expose a single observable
/// progress signal the UI can bind to.
///
/// Soft-fail per image — if one variant fails (rate limit, moderation,
/// transient network), the others land normally and the manifest records
/// the partial set. Mehdi can hit "Regenerate" on any single tile later.
@MainActor
@Observable
public final class VisualBoardController {
    public static let shared = VisualBoardController()

    public enum Phase: String, Sendable {
        case idle
        case composingPrompts
        case generatingImages
        case completed
        case failed
    }

    public private(set) var phase: Phase = .idle
    public private(set) var manifest: VisualBoardManifest?
    public private(set) var error: String?

    /// Number of images successfully written so far in the current run.
    public private(set) var completedImages: Int = 0
    /// Total number of images the current run will attempt.
    public private(set) var totalImages: Int = 0

    private let promptBuilder: VisualPromptBuilder
    private let imageClient: OpenAIImageClient
    private var currentTask: Task<Void, Never>?

    /// Categories included in the default board.
    public static let defaultCategories: [VisualConcept.Kind] = [
        .logo, .homepage, .lifestyle, .appScreen
    ]

    /// Variants per category (3 × 4 categories = 12 images per board).
    public static let defaultVariantsPerCategory: Int = 3

    public init(
        promptBuilder: VisualPromptBuilder? = nil,
        imageClient: OpenAIImageClient? = nil
    ) {
        self.promptBuilder = promptBuilder ?? VisualPromptBuilder()
        self.imageClient = imageClient ?? OpenAIImageClient()
    }

    public var isRunning: Bool {
        switch phase {
        case .idle, .completed, .failed: return false
        case .composingPrompts, .generatingImages: return true
        }
    }

    public var progressLabel: String {
        switch phase {
        case .idle:              return "Prêt à maquetter"
        case .composingPrompts:  return "Claude compose les briefs visuels…"
        case .generatingImages:  return "GPT Image 2 génère \(completedImages)/\(totalImages)…"
        case .completed:         return "Board prêt"
        case .failed:            return "Échec de génération"
        }
    }

    public func cancel() {
        currentTask?.cancel()
        currentTask = nil
        phase = .idle
    }

    /// Kick off a new board run. Loads any existing manifest first so the
    /// UI can show the previous board while the new one regenerates.
    public func generateBoard(
        for client: Node,
        report: AuditReport,
        quality: OpenAIImageQuality = .high,
        categories: [VisualConcept.Kind] = VisualBoardController.defaultCategories,
        variantsPerCategory: Int = VisualBoardController.defaultVariantsPerCategory
    ) {
        cancel()
        error = nil
        manifest = AssetStore.readManifest(for: client.id)
        phase = .composingPrompts
        completedImages = 0
        totalImages = categories.count * variantsPerCategory

        let clientID = client.id
        let clientName = client.title
        currentTask = Task { [weak self] in
            await self?.execute(
                report: report,
                clientID: clientID,
                clientName: clientName,
                categories: categories,
                variantsPerCategory: variantsPerCategory,
                quality: quality
            )
        }
    }

    /// Regenerate a single tile (same category + variant index) without
    /// touching the others. The manifest gets atomically rewritten with
    /// the replacement concept.
    public func regenerate(
        concept: VisualConcept,
        for client: Node,
        report: AuditReport,
        quality: OpenAIImageQuality = .high
    ) {
        let clientID = client.id
        let clientName = client.title
        currentTask = Task { [weak self] in
            await self?.replaceOne(
                concept: concept,
                report: report,
                clientID: clientID,
                clientName: clientName,
                quality: quality
            )
        }
    }

    // MARK: - Orchestration

    private func execute(
        report: AuditReport,
        clientID: UUID,
        clientName: String,
        categories: [VisualConcept.Kind],
        variantsPerCategory: Int,
        quality: OpenAIImageQuality
    ) async {
        do {
            // Step 1: ask Claude for prompts in each category, sequentially
            // so we keep the cost predictable (4 small Claude calls).
            phase = .composingPrompts
            var allConcepts: [VisualConcept] = []
            for category in categories {
                try Task.checkCancellation()
                let prompts = try await promptBuilder.buildPrompts(
                    for: report,
                    kind: category,
                    variants: variantsPerCategory
                )
                for (idx, prompt) in prompts.enumerated() {
                    allConcepts.append(VisualConcept(
                        kind: category,
                        variant: idx + 1,
                        prompt: prompt,
                        filename: "\(category.rawValue)-\(idx + 1).png"
                    ))
                }
            }

            // Step 2: hit GPT Image 2 once per concept. We pace them at 1
            // concurrent call so we don't trip the rate-limit on low-tier
            // OpenAI accounts; the throughput hit is acceptable since
            // each call already takes 15-60s on `high` quality.
            phase = .generatingImages
            var writtenConcepts: [VisualConcept] = []
            for concept in allConcepts {
                try Task.checkCancellation()
                do {
                    let data = try await imageClient.generate(
                        prompt: concept.prompt,
                        size: concept.kind.preferredSize,
                        quality: quality
                    )
                    _ = try AssetStore.writeImage(
                        data: data,
                        filename: concept.filename,
                        for: clientID
                    )
                    writtenConcepts.append(concept)
                } catch {
                    // Skip this concept — surface in manifest as missing
                    // (caller can hit Regenerate later). One failure
                    // doesn't sink the whole board.
                    continue
                }
                completedImages += 1
            }

            let costEstimate = Double(writtenConcepts.count) * quality.indicativeCostPerImageEUR
            let finalManifest = VisualBoardManifest(
                clientNodeID: clientID,
                clientName: clientName,
                concepts: writtenConcepts,
                qualityUsed: quality,
                totalCostEUR: costEstimate
            )
            _ = try AssetStore.writeManifest(finalManifest)

            self.manifest = finalManifest
            self.phase = .completed
        } catch is CancellationError {
            self.phase = .idle
        } catch {
            self.error = error.localizedDescription
            self.phase = .failed
        }
    }

    private func replaceOne(
        concept: VisualConcept,
        report: AuditReport,
        clientID: UUID,
        clientName: String,
        quality: OpenAIImageQuality
    ) async {
        // Reuse the same prompt by default — the user can edit later or
        // ask Claude for a different angle by hitting Regenerate again,
        // which would re-prompt Claude. For V1 we just re-render.
        phase = .generatingImages
        do {
            let data = try await imageClient.generate(
                prompt: concept.prompt,
                size: concept.kind.preferredSize,
                quality: quality
            )
            _ = try AssetStore.writeImage(
                data: data,
                filename: concept.filename,
                for: clientID
            )

            // Update manifest: keep all other concepts, swap this one.
            var current = manifest ?? VisualBoardManifest(
                clientNodeID: clientID,
                clientName: clientName,
                concepts: [],
                qualityUsed: quality
            )
            var concepts = current.concepts.filter { $0.id != concept.id }
            concepts.append(VisualConcept(
                id: concept.id,
                kind: concept.kind,
                variant: concept.variant,
                prompt: concept.prompt,
                filename: concept.filename
            ))
            current.concepts = concepts
            current.qualityUsed = quality
            _ = try AssetStore.writeManifest(current)

            self.manifest = current
            self.phase = .completed
        } catch is CancellationError {
            self.phase = .idle
        } catch {
            self.error = error.localizedDescription
            self.phase = .failed
        }
    }
}
