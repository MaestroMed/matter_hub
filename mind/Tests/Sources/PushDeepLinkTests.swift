import XCTest
@testable import MIND

/// v1.0-alpha.14 — Locks the `mind://lead/<UUID>` deep-link parser
/// the APNs push tap router uses. The parser lives at file scope in
/// `RootView.swift` so the host can drive the `mindOpenLead`
/// notification without spinning up SwiftUI / SwiftData at test
/// time.
final class PushDeepLinkTests: XCTestCase {

    /// The canonical shape — `mind://lead/<UUID>` — resolves to the
    /// embedded UUID.
    func test_parse_canonicalLeadURL_returnsUUID() {
        let id = UUID()
        let url = URL(string: "mind://lead/\(id.uuidString)")!
        XCTAssertEqual(PushDeepLink.parse(url), id)
    }

    /// Uppercased host (`mind://LEAD/<id>`) still resolves — share
    /// sheet copies sometimes uppercase the host fragment.
    func test_parse_uppercasedHost_isAccepted() {
        let id = UUID()
        let url = URL(string: "MIND://LEAD/\(id.uuidString)")!
        XCTAssertEqual(PushDeepLink.parse(url), id)
    }

    /// A trailing slash (`mind://lead/<id>/`) doesn't break the
    /// parser — the slash is collapsed before the UUID candidate is
    /// resolved.
    func test_parse_trailingSlash_isAccepted() {
        let id = UUID()
        let url = URL(string: "mind://lead/\(id.uuidString)/")!
        XCTAssertEqual(PushDeepLink.parse(url), id)
    }

    /// A wrong scheme (`https://lead/<id>`) returns nil so iOS keeps
    /// routing the URL to the default handler.
    func test_parse_wrongScheme_returnsNil() {
        let id = UUID()
        let url = URL(string: "https://lead/\(id.uuidString)")!
        XCTAssertNil(PushDeepLink.parse(url))
    }

    /// A wrong host (`mind://comparison/<id>`) returns nil; the
    /// comparison deep link has its own routing branch.
    func test_parse_wrongHost_returnsNil() {
        let id = UUID()
        let url = URL(string: "mind://comparison/\(id.uuidString)")!
        XCTAssertNil(PushDeepLink.parse(url))
    }

    /// A malformed UUID returns nil so a stale share never crashes
    /// the app — it just silently no-ops the open URL.
    func test_parse_malformedUUID_returnsNil() {
        let url = URL(string: "mind://lead/not-a-uuid")!
        XCTAssertNil(PushDeepLink.parse(url))
    }
}
