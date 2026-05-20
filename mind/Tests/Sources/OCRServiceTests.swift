import XCTest
import Foundation
import CoreGraphics
@testable import Capture

/// v0.19 — Locks the public OCRService surface and the soft-fail
/// contract. Vision itself can be flaky on a fresh simulator (the
/// text-recognition model bundles may not be downloaded on the first
/// boot), so the heavy-lifting tests target the pure `assemble`
/// helper and the empty-input path — both deterministic, both run in
/// milliseconds, both lock the API shape the QuickCaptureSheet
/// relies on.
final class OCRServiceTests: XCTestCase {

    // MARK: - Soft-fail contract

    /// Empty Data must short-circuit to an empty result before
    /// `VNImageRequestHandler` ever gets invoked. The picker can
    /// surface a placeholder Data() while the user is still mid-pick,
    /// and we never want that to spin up Vision.
    func test_recognizeText_emptyData_returnsEmptyResult() async {
        let result = await OCRService.recognizeText(from: Data())
        XCTAssertEqual(result.text, "")
        XCTAssertTrue(result.blocks.isEmpty)
        XCTAssertEqual(result.confidence, 0)
    }

    /// Garbage bytes must NOT crash. Vision throws under the hood;
    /// the OCRService eats it and returns an empty OCRResult. This
    /// test guards against a future refactor that lets the error
    /// escape — Mehdi never wants Vision noise in his crash dashboard.
    func test_recognizeText_corruptData_returnsEmptyResult_noCrash() async {
        let corrupt = Data([0x00, 0x01, 0x02, 0xFF, 0xFE, 0xFD])
        let result = await OCRService.recognizeText(from: corrupt)
        XCTAssertEqual(result.text, "")
        XCTAssertEqual(result.confidence, 0)
    }

    // MARK: - Pure assembler

    /// No observations → empty result with zero confidence. This is
    /// the canonical "no text on the page" path.
    func test_assemble_emptyObservations_returnsEmpty() {
        let result = OCRService.assemble(from: [])
        XCTAssertEqual(result.text, "")
        XCTAssertTrue(result.blocks.isEmpty)
        XCTAssertEqual(result.confidence, 0)
    }

    // MARK: - Sendable + Equatable contract

    /// OCRResult must compare equal on identical inputs — drives any
    /// future `.onChange(of: result)` SwiftUI binding. Equatable
    /// conformance is the cheap insurance.
    func test_OCRResult_isEquatable_onIdenticalInputs() {
        let a = OCRResult(text: "hello", blocks: [], confidence: 0.42)
        let b = OCRResult(text: "hello", blocks: [], confidence: 0.42)
        XCTAssertEqual(a, b)
    }

    /// Different text → not equal. Sanity-check the Equatable
    /// synthesis covers the full struct.
    func test_OCRResult_inequality_onDifferentText() {
        let a = OCRResult(text: "hello", blocks: [], confidence: 0.42)
        let b = OCRResult(text: "world", blocks: [], confidence: 0.42)
        XCTAssertNotEqual(a, b)
    }

    /// OCRBlock must round-trip through Equatable too — the
    /// QuickCaptureSheet does not currently lean on this but the
    /// share-extension stretch goal of v0.19 will diff blocks.
    func test_OCRBlock_isEquatable_onIdenticalInputs() {
        let bbox = CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        let a = OCRBlock(text: "MIND", bbox: bbox, confidence: 0.91)
        let b = OCRBlock(text: "MIND", bbox: bbox, confidence: 0.91)
        XCTAssertEqual(a, b)
    }

    // MARK: - Language threading

    /// Passing a single-language array must not crash and must still
    /// soft-fail on empty input. The Share Extension will pass the
    /// device's preferred language only (`["en-US"]` for an en device)
    /// and we want that path tested.
    func test_recognizeText_singleLanguage_doesNotCrash() async {
        let result = await OCRService.recognizeText(from: Data(), languages: ["en-US"])
        XCTAssertEqual(result.text, "")
        XCTAssertEqual(result.confidence, 0)
    }
}
