import SwiftUI
import AuditKit
import DesignSystem
import VisualKit

/// Visual concept board sheet — shown from the audit report's pitch
/// card via "Maquetter le futur digital". Three states:
///   - empty (no manifest yet) → big CTA explaining the run + budget
///   - generating → progress per category
///   - completed → grid of generated PNGs with share + regenerate
struct VisualBoardView: View {
    @Environment(\.dismiss) private var dismiss

    let report: AuditReport

    @State private var controller = VisualBoardController.shared
    @State private var selectedQuality: OpenAIImageQuality = .high

    private var clientKey: String { VisualBoardKey.key(for: report.client.url) }
    private var manifest: VisualBoardManifest? { controller.manifest }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                if controller.isRunning {
                    progressCard
                } else if let manifest, !manifest.concepts.isEmpty {
                    boardContent(manifest)
                    regenerateAllCard
                } else if controller.phase == .failed {
                    failureCard
                } else {
                    introCard
                    qualityPicker
                    launchButton
                }
            }
            .padding(20)
            .padding(.bottom, 40)
        }
        .background { LiquidBackground().ignoresSafeArea() }
        .onAppear { controller.loadManifest(for: report) }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Maquetter le futur digital")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                Text(report.client.displayName)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                if let manifest = manifest, manifest.generatedAt.timeIntervalSinceNow > -3600 * 24 * 30 {
                    Text("Généré " + manifest.generatedAt.formatted(.relative(presentation: .named)))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Intro state

    private var introCard: some View {
        LiquidCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(LiquidGradient.primary)
                            .frame(width: 44, height: 44)
                        Image(systemName: "sparkles")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("12 visuels SOTA en 4 catégories")
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                        Text("Claude compose les briefs · GPT Image 2 génère.")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    bullet(icon: "app.fill", text: "3 logos concepts (squircles iOS 26)")
                    bullet(icon: "macwindow", text: "3 mockups homepage (landscape desktop)")
                    bullet(icon: "photo.fill", text: "3 photos lifestyle / ambiance")
                    bullet(icon: "iphone.gen3", text: "3 screens app mobile (portrait Liquid Glass)")
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func bullet(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(LiquidPalette.iris)
                .frame(width: 18)
            Text(text)
                .font(.system(.subheadline, design: .rounded))
        }
    }

    private var qualityPicker: some View {
        LiquidCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Qualité GPT Image 2".uppercased())
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.8)
                HStack(spacing: 8) {
                    ForEach(OpenAIImageQuality.allCases, id: \.self) { quality in
                        qualityPill(quality)
                    }
                }
                Text(budgetLabel)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func qualityPill(_ quality: OpenAIImageQuality) -> some View {
        let isSelected = selectedQuality == quality
        return Button {
            withAnimation(LiquidMetrics.spring) {
                selectedQuality = quality
            }
        } label: {
            Text(quality.displayName)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(isSelected ? .white : LiquidPalette.iris)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background {
                    Capsule().fill(isSelected
                        ? AnyShapeStyle(LiquidGradient.primary)
                        : AnyShapeStyle(LiquidPalette.lavender.opacity(0.35)))
                }
        }
        .buttonStyle(.plain)
    }

    private var budgetLabel: String {
        let count = VisualBoardController.defaultCategories.count
            * VisualBoardController.defaultVariantsPerCategory
        let cost = Double(count) * selectedQuality.indicativeCostPerImageEUR
        return String(format: "Budget estimé : %.2f € pour %d visuels", cost, count)
    }

    private var launchButton: some View {
        LiquidButton(title: "Générer le board", systemImage: "sparkles") {
            controller.generateBoard(for: report, quality: selectedQuality)
        }
    }

    // MARK: - Progress state

    private var progressCard: some View {
        LiquidCard(cornerRadius: 22) {
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                    .tint(LiquidPalette.iris)
                Text(controller.progressLabel)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .multilineTextAlignment(.center)
                if controller.totalImages > 0 {
                    Text("\(controller.completedImages) / \(controller.totalImages) visuels")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                Button("Annuler") {
                    controller.cancel()
                }
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(.secondary)
            }
            .padding(28)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Failure state

    private var failureCard: some View {
        LiquidCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Échec de génération", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.orange)
                if let error = controller.error {
                    Text(error)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                LiquidButton(title: "Réessayer", systemImage: "arrow.clockwise") {
                    controller.generateBoard(for: report, quality: selectedQuality)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Completed state

    @ViewBuilder
    private func boardContent(_ manifest: VisualBoardManifest) -> some View {
        ForEach(VisualConcept.Kind.allCases, id: \.self) { kind in
            let concepts = manifest.concepts(of: kind)
            if !concepts.isEmpty {
                categorySection(kind: kind, concepts: concepts)
            }
        }
        if let cost = manifest.totalCostEUR {
            Text(String(format: "Coût estimé : %.2f € · qualité %@", cost, manifest.qualityUsed.displayName))
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.tertiary)
                .padding(.leading, 4)
        }
    }

    private func categorySection(kind: VisualConcept.Kind, concepts: [VisualConcept]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(kind.displayName.uppercased())
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.8)
                .padding(.leading, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(concepts) { concept in
                        ConceptTile(
                            concept: concept,
                            clientKey: clientKey,
                            kind: kind,
                            onRegenerate: {
                                controller.regenerate(
                                    concept: concept,
                                    for: report,
                                    quality: manifest?.qualityUsed ?? .high
                                )
                            }
                        )
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private var regenerateAllCard: some View {
        LiquidButton(title: "Régénérer tout le board", systemImage: "arrow.clockwise") {
            controller.generateBoard(for: report, quality: selectedQuality)
        }
    }
}

// MARK: - Concept tile

private struct ConceptTile: View {
    let concept: VisualConcept
    let clientKey: String
    let kind: VisualConcept.Kind
    let onRegenerate: () -> Void

    private var tileSize: CGSize {
        switch kind {
        case .logo:      return CGSize(width: 160, height: 160)
        case .appScreen: return CGSize(width: 140, height: 220)
        case .homepage, .lifestyle: return CGSize(width: 260, height: 160)
        }
    }

    private var imageURL: URL? {
        AssetStore.imageURL(filename: concept.filename, for: clientKey)
    }

    var body: some View {
        let url = imageURL
        return Menu {
            if let url {
                ShareLink(item: url, preview: SharePreview(kind.displayName)) {
                    Label("Partager", systemImage: "square.and.arrow.up")
                }
            }
            Button {
                onRegenerate()
            } label: {
                Label("Régénérer ce visuel", systemImage: "arrow.clockwise")
            }
        } label: {
            tileBody(url: url)
        }
    }

    @ViewBuilder
    private func tileBody(url: URL?) -> some View {
        if let url, let uiImage = UIImage(contentsOfFile: url.path) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: tileSize.width, height: tileSize.height)
                .clipShape(RoundedRectangle(
                    cornerRadius: kind == .logo ? 36 : 18,
                    style: .continuous
                ))
                .overlay {
                    RoundedRectangle(cornerRadius: kind == .logo ? 36 : 18, style: .continuous)
                        .stroke(LiquidGradient.glassStroke, lineWidth: 0.8)
                }
                .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
        } else {
            RoundedRectangle(cornerRadius: kind == .logo ? 36 : 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .frame(width: tileSize.width, height: tileSize.height)
                .overlay {
                    VStack(spacing: 6) {
                        Image(systemName: "photo")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                        Text("image manquante")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
        }
    }
}
