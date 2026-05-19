import XCTest
@testable import GraphCore

/// Contract tests for the cross-process share queue used by
/// MINDShareExtension → MIND host app. We work against an isolated
/// temp file (never the real App Group container) so test runs are
/// hermetic and don't surface fake share captures inside the dev app.
final class ShareInboxTests: XCTestCase {

    // MARK: - Test scaffolding

    private var queueURL: URL!

    override func setUp() {
        super.setUp()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShareInboxTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        queueURL = directory.appendingPathComponent("ShareInbox.json")
    }

    override func tearDown() {
        if let queueURL {
            try? FileManager.default.removeItem(
                at: queueURL.deletingLastPathComponent()
            )
        }
        queueURL = nil
        super.tearDown()
    }

    // MARK: - Enqueue / drain roundtrip

    func test_enqueue_thenDrain_returnsExactPayload() {
        let payload = ShareInbox.Payload(
            url: URL(string: "https://stripe.com")!,
            text: "Check Stripe pricing page",
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertTrue(ShareInbox.enqueue(payload, at: queueURL))
        let drained = ShareInbox.drain(at: queueURL)

        XCTAssertEqual(drained.count, 1)
        XCTAssertEqual(drained.first?.url, payload.url)
        XCTAssertEqual(drained.first?.text, payload.text)
        XCTAssertEqual(drained.first?.id, payload.id)
    }

    func test_drain_clearsTheQueue() {
        let payload = ShareInbox.Payload(url: URL(string: "https://example.com"))
        _ = ShareInbox.enqueue(payload, at: queueURL)

        _ = ShareInbox.drain(at: queueURL)
        XCTAssertTrue(
            ShareInbox.peek(at: queueURL).isEmpty,
            "drain must empty the queue so the next call doesn't re-yield items"
        )
    }

    func test_enqueue_preservesInsertionOrder() {
        let first = ShareInbox.Payload(url: URL(string: "https://one.com"))
        let second = ShareInbox.Payload(url: URL(string: "https://two.com"))
        let third = ShareInbox.Payload(url: URL(string: "https://three.com"))

        _ = ShareInbox.enqueue(first, at: queueURL)
        _ = ShareInbox.enqueue(second, at: queueURL)
        _ = ShareInbox.enqueue(third, at: queueURL)

        let drained = ShareInbox.drain(at: queueURL)
        XCTAssertEqual(drained.map(\.url), [first.url, second.url, third.url])
    }

    func test_enqueue_capsAt10Payloads_droppingOldest() {
        // Enqueue 12 payloads, expect last 10 to survive.
        var enqueued: [ShareInbox.Payload] = []
        for index in 0..<12 {
            let p = ShareInbox.Payload(
                url: URL(string: "https://item-\(index).com")!
            )
            enqueued.append(p)
            _ = ShareInbox.enqueue(p, at: queueURL)
        }

        let remaining = ShareInbox.peek(at: queueURL)
        XCTAssertEqual(remaining.count, ShareInbox.maxPendingPayloads)
        // The first two (indices 0 and 1) should be the casualties.
        XCTAssertEqual(remaining.first?.url, enqueued[2].url)
        XCTAssertEqual(remaining.last?.url, enqueued[11].url)
    }

    func test_clear_emptiesTheQueueWithoutReturningPayloads() {
        _ = ShareInbox.enqueue(
            ShareInbox.Payload(url: URL(string: "https://x.com")),
            at: queueURL
        )
        XCTAssertTrue(ShareInbox.clear(at: queueURL))
        XCTAssertTrue(ShareInbox.peek(at: queueURL).isEmpty)
    }

    // MARK: - Payload accessors

    func test_titleCandidate_prefersURLHostOverText() {
        let payload = ShareInbox.Payload(
            url: URL(string: "https://notion.so/page/123"),
            text: "Random comment"
        )
        XCTAssertEqual(payload.titleCandidate, "notion.so")
    }

    func test_titleCandidate_fallsBackToFirstLineOfText() {
        let payload = ShareInbox.Payload(
            url: nil,
            text: "First line of thought\nSecond line of detail"
        )
        XCTAssertEqual(payload.titleCandidate, "First line of thought")
    }

    func test_titleCandidate_fallsBackToSharedItemWhenEmpty() {
        let payload = ShareInbox.Payload(url: nil, text: nil)
        XCTAssertEqual(payload.titleCandidate, "Shared item")
    }

    func test_contentBody_combinesURLAndText() {
        let payload = ShareInbox.Payload(
            url: URL(string: "https://stripe.com/pricing"),
            text: "Need this for the audit pitch"
        )
        XCTAssertTrue(payload.contentBody.contains("stripe.com/pricing"))
        XCTAssertTrue(payload.contentBody.contains("audit pitch"))
    }

    // MARK: - Known-host extraction

    func test_knownClientName_matchesBareHost() {
        let url = URL(string: "https://stripe.com")!
        XCTAssertEqual(ShareInbox.knownClientName(for: url), "Stripe")
    }

    func test_knownClientName_matchesSubdomain() {
        let url = URL(string: "https://dashboard.stripe.com/payments")!
        XCTAssertEqual(ShareInbox.knownClientName(for: url), "Stripe")
    }

    func test_knownClientName_stripsLeadingWWW() {
        let url = URL(string: "https://www.notion.so/team/home")!
        XCTAssertEqual(ShareInbox.knownClientName(for: url), "Notion")
    }

    func test_knownClientName_returnsNilForUnknownHost() {
        let url = URL(string: "https://random-blog.example.fr/article")!
        XCTAssertNil(ShareInbox.knownClientName(for: url))
    }

    func test_knownClientName_isCaseInsensitive() {
        let url = URL(string: "https://Stripe.COM/pricing")!
        XCTAssertEqual(ShareInbox.knownClientName(for: url), "Stripe")
    }
}
