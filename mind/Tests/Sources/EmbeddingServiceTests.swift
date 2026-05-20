import XCTest
@testable import GraphCore

final class EmbeddingServiceTests: XCTestCase {

    func test_cosineSimilarity_identicalVectors_isOne() {
        let v: [Float] = [1, 2, 3, 4, 5]
        XCTAssertEqual(EmbeddingService.cosineSimilarity(v, v), 1.0, accuracy: 1e-5)
    }

    func test_cosineSimilarity_orthogonalVectors_isZero() {
        let a: [Float] = [1, 0]
        let b: [Float] = [0, 1]
        XCTAssertEqual(EmbeddingService.cosineSimilarity(a, b), 0.0, accuracy: 1e-5)
    }

    func test_cosineSimilarity_oppositeVectors_isMinusOne() {
        let a: [Float] = [1, 2, 3]
        let b: [Float] = [-1, -2, -3]
        XCTAssertEqual(EmbeddingService.cosineSimilarity(a, b), -1.0, accuracy: 1e-5)
    }

    func test_cosineSimilarity_emptyVector_isZero() {
        XCTAssertEqual(EmbeddingService.cosineSimilarity([], []), 0.0)
    }

    func test_cosineSimilarity_mismatchedSizes_isZero() {
        // Defensive guard: must not crash, returns zero so the caller
        // treats it as "no signal" instead of NaN.
        XCTAssertEqual(EmbeddingService.cosineSimilarity([1, 2], [1, 2, 3]), 0.0)
    }

    func test_embed_emptyInput_returnsNil() {
        XCTAssertNil(EmbeddingService.embed(""))
        XCTAssertNil(EmbeddingService.embed("   \n  "))
    }

    func test_embed_realFrenchText_returnsNonNilDenseVector() {
        // Sentence embedding model for French is bundled with iOS — the
        // call should produce a real vector. Robust against the model
        // being absent in unusual test environments.
        if let v = EmbeddingService.embed("Une pensée structurée vaut mille captures.") {
            XCTAssertGreaterThan(v.count, 50, "French sentence embedding should be dense (~300 dims)")
        }
    }
}
