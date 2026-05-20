import XCTest
@testable import GraphCore

/// v1.0-alpha.8 — Locks the Project Health Pulse classifier contract.
///
/// `HealthClassifier.classify(...)` is a pure mapping from
/// `(statusCode, responseTimeMs)` to `HealthStatus`. Every Cockpit
/// status dot, every "what's on fire" sort, every accessibility label
/// reads from it — so the test matrix has to cover every bucket
/// boundary exactly.
final class HealthClassifierTests: XCTestCase {

    // MARK: - Online (fast 2xx)

    /// A 200 OK landing well under the 1500 ms threshold is the canonical
    /// healthy site path. Surface as `.online` — the green dot.
    func test_classify_fastTwoHundred_isOnline() {
        XCTAssertEqual(
            HealthClassifier.classify(statusCode: 200, responseTimeMs: 120),
            .online
        )
    }

    /// 299 is the last 2xx code. Should still bucket as online when
    /// fast — the classifier's inclusive lower / exclusive upper
    /// boundary is what we lock here so a future "improve 2xx" tweak
    /// doesn't accidentally re-bucket 299 as a redirect.
    func test_classify_twoHundredNinetyNine_isOnline() {
        XCTAssertEqual(
            HealthClassifier.classify(statusCode: 299, responseTimeMs: 50),
            .online
        )
    }

    // MARK: - Degraded (slow 2xx + 3xx redirects)

    /// A 200 OK above the 1500 ms degraded threshold turns the dot
    /// yellow. The threshold itself is inclusive — `>= 1500` flips
    /// the bucket — so the exact boundary value pins to `.degraded`.
    func test_classify_slowTwoHundred_isDegraded() {
        XCTAssertEqual(
            HealthClassifier.classify(statusCode: 200, responseTimeMs: 1500),
            .degraded
        )
    }

    /// Edge case: a 200 right at the threshold (`==`) — still
    /// `.degraded`. Locks the `>=` boundary contract.
    func test_classify_twoHundredAtExactThreshold_isDegraded() {
        XCTAssertEqual(
            HealthClassifier.classify(
                statusCode: 200,
                responseTimeMs: HealthClassifier.defaultDegradedThresholdMs
            ),
            .degraded
        )
    }

    /// Just under the threshold stays online — the inverse of the
    /// boundary test above.
    func test_classify_twoHundredJustUnderThreshold_isOnline() {
        XCTAssertEqual(
            HealthClassifier.classify(
                statusCode: 200,
                responseTimeMs: HealthClassifier.defaultDegradedThresholdMs - 1
            ),
            .online
        )
    }

    /// 301 (permanent redirect) and 302 (temp redirect) both bucket
    /// as `.degraded`. The site is reachable but the configured host
    /// points elsewhere — Mehdi should fix the host value.
    func test_classify_redirect_isDegraded() {
        XCTAssertEqual(
            HealthClassifier.classify(statusCode: 301, responseTimeMs: 80),
            .degraded
        )
        XCTAssertEqual(
            HealthClassifier.classify(statusCode: 302, responseTimeMs: 80),
            .degraded
        )
    }

    /// Custom threshold parameter overrides the default. A 200 ms
    /// response with a 100 ms threshold still buckets as `.degraded`.
    /// Locks the parametrisation contract so future per-project
    /// overrides plug in cleanly.
    func test_classify_customThreshold_overrides() {
        XCTAssertEqual(
            HealthClassifier.classify(
                statusCode: 200,
                responseTimeMs: 200,
                degradedThresholdMs: 100
            ),
            .degraded
        )
    }

    // MARK: - Error (4xx / 5xx)

    /// 404 Not Found buckets as `.error` — red dot. The site is
    /// reachable but the homepage path is gone.
    func test_classify_fourOhFour_isError() {
        XCTAssertEqual(
            HealthClassifier.classify(statusCode: 404, responseTimeMs: 80),
            .error
        )
    }

    /// 500 Internal Server Error — also `.error`, also red.
    func test_classify_fiveHundred_isError() {
        XCTAssertEqual(
            HealthClassifier.classify(statusCode: 500, responseTimeMs: 80),
            .error
        )
    }

    /// 503 Service Unavailable — common Vercel outage signature.
    /// Same `.error` bucket.
    func test_classify_fiveOhThree_isError() {
        XCTAssertEqual(
            HealthClassifier.classify(statusCode: 503, responseTimeMs: 80),
            .error
        )
    }

    // MARK: - Offline (transport failure)

    /// Sentinel transport-failure status code (-1) → `.offline`. This
    /// is the bucket the probe layer uses when the URL session itself
    /// threw before any HTTP status came back.
    func test_classify_transportFailure_isOffline() {
        XCTAssertEqual(
            HealthClassifier.classify(
                statusCode: HealthClassifier.transportFailureStatusCode,
                responseTimeMs: 0
            ),
            .offline
        )
    }

    /// Defensive: a wholly-unexpected negative status (other than the
    /// documented sentinel) buckets as `.offline` rather than crashing
    /// the dot. The 0-199 range also falls through to offline.
    func test_classify_unexpectedNegative_isOffline() {
        XCTAssertEqual(
            HealthClassifier.classify(statusCode: -99, responseTimeMs: 0),
            .offline
        )
        XCTAssertEqual(
            HealthClassifier.classify(statusCode: 100, responseTimeMs: 0),
            .offline
        )
    }

    // MARK: - HealthStatus severity ordering

    /// The Cockpit "what's on fire" sort relies on `.offline` ranking
    /// strictly below every other bucket. If a future refactor
    /// re-orders the enum cases, the test breaks and we catch the
    /// invariant break before users do.
    func test_severityRank_offlineRanksMostCritical() {
        XCTAssertLessThan(HealthStatus.offline.severityRank,  HealthStatus.error.severityRank)
        XCTAssertLessThan(HealthStatus.error.severityRank,    HealthStatus.degraded.severityRank)
        XCTAssertLessThan(HealthStatus.degraded.severityRank, HealthStatus.online.severityRank)
        XCTAssertLessThan(HealthStatus.online.severityRank,   HealthStatus.unknown.severityRank)
    }

    // MARK: - HealthPulseHelpers.sortByCriticalFirst

    /// Sorting mixes by status (offline > error > degraded > online >
    /// unknown) AND by checkedAt within a status. The newer pulse
    /// inside the same bucket lands first.
    func test_sortByCriticalFirst_groupsBySeverity_thenByDateDesc() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let p1 = HealthPulse(projectID: UUID(), host: "a", checkedAt: now, statusCode: 200, responseTimeMs: 80, status: .online)
        let p2 = HealthPulse(projectID: UUID(), host: "b", checkedAt: now.addingTimeInterval(60), statusCode: 500, responseTimeMs: 40, status: .error)
        let p3 = HealthPulse(projectID: UUID(), host: "c", checkedAt: now, statusCode: -1, responseTimeMs: 0, status: .offline)
        let p4 = HealthPulse(projectID: UUID(), host: "d", checkedAt: now.addingTimeInterval(120), statusCode: 500, responseTimeMs: 40, status: .error)

        let sorted = HealthPulseHelpers.sortByCriticalFirst([p1, p2, p3, p4])

        XCTAssertEqual(sorted[0].host, "c", ".offline should rank first")
        XCTAssertEqual(sorted[1].host, "d", "Two .error pulses: newer first (now+120)")
        XCTAssertEqual(sorted[2].host, "b", "Older .error second (now+60)")
        XCTAssertEqual(sorted[3].host, "a", ".online stays last in this mix")
    }

    /// Empty input round-trips to empty output without crashing the
    /// sort. Defensive contract.
    func test_sortByCriticalFirst_emptyInput_isEmpty() {
        XCTAssertEqual(HealthPulseHelpers.sortByCriticalFirst([]).count, 0)
    }

    // MARK: - HealthPulse Codable

    /// JSON round-trips every field — the on-disk store relies on
    /// this. If a field drops out of the Codable synthesis, the
    /// cached pulse loses precision on the next launch.
    func test_healthPulse_codableRoundTrip_preservesEveryField() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let pulse = HealthPulse(
            id: UUID(uuidString: "DEADBEEF-0000-0000-0000-000000000001")!,
            projectID: UUID(uuidString: "DEADBEEF-0000-0000-0000-000000000002")!,
            host: "www.example.com",
            checkedAt: now,
            statusCode: 200,
            responseTimeMs: 312,
            status: .online
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(pulse)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(HealthPulse.self, from: data)

        XCTAssertEqual(decoded, pulse,
                       "Round-trip must preserve every Codable field byte-for-byte.")
    }
}
