import Foundation
import Vision
import CoreGraphics

/// v0.19 — On-device OCR via Apple's Vision framework. Wraps
/// `VNRecognizeTextRequest` behind a pure async API that the
/// QuickCaptureSheet calls when the user picks a photo (whiteboard,
/// business card, screenshot, handwritten note). French and English
/// are both wired by default — Vision's `.accurate` recognition level
/// handles latin-script handwriting + printed text in either locale.
///
/// Why a thin facade
/// -----------------
/// The Capture module is the only call site today, but v0.3's Share
/// Extension (stretch goal at the bottom of the v0.19 spec) will want
/// the same primitive when an image is shared into MIND. Keeping the
/// surface a single static async function — Data in, OCRResult out —
/// means both call sites get the same soft-fail behaviour with zero
/// dependency drift.
///
/// Soft-fail contract
/// ------------------
/// Vision can fail for a dozen reasons (corrupt JPEG, HEIC the
/// simulator can't decode, the photo has zero recognisable glyphs).
/// None of those are interesting to the user — the user just wants
/// "the text" or "nothing happened". We collapse every Vision error
/// into an empty `OCRResult` and let the caller decide whether to
/// surface a localized "no text found" empty-state. The breadcrumb
/// path is the right place to inspect failures post-hoc.
public enum OCRService {

    /// Recognise text in the supplied image data. `languages` follows
    /// BCP-47 (`fr-FR`, `en-US`, etc.) — order matters: the first entry
    /// gets the highest weight when Vision arbitrates ambiguous glyphs.
    /// The default `["fr-FR", "en-US"]` matches Mehdi's bilingual
    /// note-taking habit; the share extension will likely pass the
    /// user's preferred language first in a future iteration.
    public static func recognizeText(
        from imageData: Data,
        languages: [String] = ["fr-FR", "en-US"]
    ) async -> OCRResult {
        // Empty / zero-byte input is a real path — PhotosPicker can
        // surface a placeholder Data() while the user is still in the
        // picker. Short-circuit before paying for a VNImageRequestHandler.
        guard !imageData.isEmpty else {
            return OCRResult(text: "", blocks: [], confidence: 0)
        }

        // Vision's request callback is delivered on an arbitrary queue.
        // Bridge it into the async/await world with a single-resume
        // continuation. Vision can fire BOTH the request completion
        // (with an error) AND throw from `perform(_:)` for the same
        // failure mode (corrupt input data is the canonical case), so
        // we run the synchronous `perform` first inside a Task on a
        // detached queue and only resume the continuation from the
        // request callback. If `perform` throws, the request callback
        // is also invoked synchronously with the error, so the single
        // resume path stays correct.
        return await withCheckedContinuation { continuation in
            // Box-style "did we resume yet" guard. `perform(_:)` is
            // synchronous and invokes the completion handler on the
            // same thread before returning, so a non-atomic Bool is
            // sufficient — no cross-thread race window exists between
            // the two code paths that could both call resume.
            var resumed = false
            let resume: (OCRResult) -> Void = { result in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: result)
            }

            let request = VNRecognizeTextRequest { request, error in
                if error != nil {
                    resume(OCRResult(text: "", blocks: [], confidence: 0))
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                resume(Self.assemble(from: observations))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = languages

            let handler = VNImageRequestHandler(data: imageData, options: [:])
            do {
                try handler.perform([request])
            } catch {
                resume(OCRResult(text: "", blocks: [], confidence: 0))
            }
        }
    }

    // MARK: - Pure helpers (testable without Vision)

    /// Convert Vision observations into the public `OCRResult`. Pulled
    /// out as `internal` so tests can lock the assembly contract
    /// independent of whether the simulator has Vision text models
    /// pre-installed.
    static func assemble(from observations: [VNRecognizedTextObservation]) -> OCRResult {
        guard !observations.isEmpty else {
            return OCRResult(text: "", blocks: [], confidence: 0)
        }
        var blocks: [OCRBlock] = []
        var lines: [String] = []
        var confidenceSum: Double = 0
        var confidenceWeight: Double = 0
        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string
            let confidence = candidate.confidence
            blocks.append(OCRBlock(text: text, bbox: observation.boundingBox, confidence: confidence))
            lines.append(text)
            confidenceSum += Double(confidence)
            confidenceWeight += 1
        }
        let joined = lines.joined(separator: "\n")
        let avg = confidenceWeight > 0 ? confidenceSum / confidenceWeight : 0
        return OCRResult(text: joined, blocks: blocks, confidence: avg)
    }
}

/// Result returned by `OCRService.recognizeText`. Sendable so it can
/// cross actor boundaries cleanly (Vision runs on its own queue, the
/// caller is on MainActor).
public struct OCRResult: Sendable, Equatable {
    /// All recognised lines joined with `\n`, ready to drop into a Node.
    public let text: String
    /// One entry per `VNRecognizedTextObservation` — useful for layout-
    /// aware rendering in a future iteration (highlight regions on the
    /// photo, etc.).
    public let blocks: [OCRBlock]
    /// Average confidence across recognised blocks, in [0, 1]. 0 means
    /// "no text was found".
    public let confidence: Double

    public init(text: String, blocks: [OCRBlock], confidence: Double) {
        self.text = text
        self.blocks = blocks
        self.confidence = confidence
    }
}

/// One recognised text region. `bbox` is in Vision's normalised
/// coordinate space (origin bottom-left, [0,1]²), the same convention
/// used by every other Vision request — callers that overlay the
/// detection on a `UIImage` should flip Y.
public struct OCRBlock: Sendable, Equatable {
    public let text: String
    public let bbox: CGRect
    public let confidence: Float

    public init(text: String, bbox: CGRect, confidence: Float) {
        self.text = text
        self.bbox = bbox
        self.confidence = confidence
    }
}
