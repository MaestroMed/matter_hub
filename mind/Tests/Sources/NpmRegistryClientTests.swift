import XCTest
@testable import AuditKit

/// v1.0-alpha.10 — Pure URL/cache-key/Codable tests for the
/// `NpmRegistryClient`. The actor's network path is exercised live
/// at the integration layer (out of scope for unit tests); here we
/// lock the URL shape so the registry call never targets a typo'd
/// endpoint.
final class NpmRegistryClientTests: XCTestCase {

    func test_latestURL_buildsExpectedShape() throws {
        let url = try XCTUnwrap(NpmRegistryClient.latestURL(packageName: "react"))
        XCTAssertEqual(url.absoluteString, "https://registry.npmjs.org/react/latest")
    }

    /// Scoped packages keep their slash through percent-encoding.
    func test_latestURL_handlesScopedPackages() throws {
        let url = try XCTUnwrap(NpmRegistryClient.latestURL(packageName: "@stripe/stripe-js"))
        // The slash is preserved; `@` may or may not be encoded.
        // The registry accepts both shapes.
        XCTAssertTrue(url.absoluteString.contains("/latest"))
        XCTAssertTrue(url.absoluteString.contains("stripe-js"))
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "registry.npmjs.org")
    }

    /// Empty / whitespace-only name returns nil so the caller can
    /// short-circuit before firing a bogus request.
    func test_latestURL_rejectsEmptyAndWhitespace() {
        XCTAssertNil(NpmRegistryClient.latestURL(packageName: ""))
        XCTAssertNil(NpmRegistryClient.latestURL(packageName: "   "))
    }

    /// Scoped names collapse their slash to `_` in the cache key so
    /// the on-disk filename is filesystem-safe.
    func test_cacheKey_collapsesScopedSlash() {
        XCTAssertEqual(
            NpmRegistryClient.cacheKey(packageName: "@stripe/stripe-js"),
            "@stripe_stripe-js"
        )
        XCTAssertEqual(
            NpmRegistryClient.cacheKey(packageName: "react"),
            "react"
        )
        XCTAssertEqual(
            NpmRegistryClient.cacheKey(packageName: ""),
            "_empty"
        )
    }

    /// `NpmPackageInfo` Codable round-trip preserves size when
    /// present and nil when absent.
    func test_npmPackageInfo_codableRoundTrip() throws {
        let withSize = NpmRegistryClient.NpmPackageInfo(
            name: "lodash",
            version: "4.17.21",
            approximateSizeKB: 1480
        )
        let withoutSize = NpmRegistryClient.NpmPackageInfo(
            name: "lodash",
            version: "4.17.21",
            approximateSizeKB: nil
        )
        let dataWith = try JSONEncoder().encode(withSize)
        let dataWithout = try JSONEncoder().encode(withoutSize)
        let decodedWith = try JSONDecoder().decode(NpmRegistryClient.NpmPackageInfo.self, from: dataWith)
        let decodedWithout = try JSONDecoder().decode(NpmRegistryClient.NpmPackageInfo.self, from: dataWithout)

        XCTAssertEqual(decodedWith, withSize)
        XCTAssertEqual(decodedWithout, withoutSize)
        XCTAssertNil(decodedWithout.approximateSizeKB)
    }
}
