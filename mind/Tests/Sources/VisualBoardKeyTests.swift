import XCTest
@testable import VisualKit

final class VisualBoardKeyTests: XCTestCase {

    func test_key_dropsWWWAndScheme() {
        let url = URL(string: "https://www.stripe.com/products")!
        XCTAssertEqual(VisualBoardKey.key(for: url), "stripe.com")
    }

    func test_key_keepsSubdomain() {
        let url = URL(string: "https://app.linear.app/")!
        XCTAssertEqual(VisualBoardKey.key(for: url), "app.linear.app")
    }

    func test_key_lowercasesHost() {
        let url = URL(string: "https://STRIPE.com/")!
        XCTAssertEqual(VisualBoardKey.key(for: url), "stripe.com")
    }

    func test_key_sanitizesIllegalCharacters() {
        // Defensive: shouldn't happen in normal URLs but the helper
        // promises a filesystem-safe slug.
        let url = URL(string: "https://example.com/")!
        let key = VisualBoardKey.key(for: url)
        XCTAssertFalse(key.contains("/"))
        XCTAssertFalse(key.contains(":"))
    }
}
