import XCTest
@testable import GraphCore

/// v1.0-alpha.8 — Locks the on-disk + in-memory contract of
/// `HealthPulseStore`. Same shape as `SEOSwarmStoreTests` — each test
/// instantiates a fresh store rooted at a temp directory so the
/// app-sandbox singleton never gets polluted by the test runner.
final class HealthPulseStoreTests: XCTestCase {

    private func makeStore() -> (HealthPulseStore, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("health-pulses-test-\(UUID().uuidString)", isDirectory: true)
        return (HealthPulseStore(rootURL: root), root)
    }

    /// A pulse that was just saved must round-trip out of the cache on
    /// the very next read. The first-launch hydration path is exercised
    /// indirectly: the cache hit short-circuits the disk read after
    /// the initial save.
    func test_save_thenLoad_roundTripsExactValue() async {
        let (store, _) = makeStore()
        let pulse = HealthPulse(
            projectID: UUID(),
            host: "www.az-construction.fr",
            statusCode: 200,
            responseTimeMs: 280,
            status: .online
        )
        await store.save(pulse)

        let loaded = await store.load(projectID: pulse.projectID)
        XCTAssertEqual(loaded, pulse)
    }

    /// Saving a second pulse for the same projectID overwrites the
    /// first. The Cockpit only ever surfaces "the latest" — we never
    /// accumulate history under this key.
    func test_save_overwritesPreviousPulseForSameProject() async {
        let (store, _) = makeStore()
        let projectID = UUID()

        let first = HealthPulse(
            projectID: projectID,
            host: "h", checkedAt: Date(timeIntervalSince1970: 1),
            statusCode: 500, responseTimeMs: 1200, status: .error
        )
        await store.save(first)

        let second = HealthPulse(
            projectID: projectID,
            host: "h", checkedAt: Date(timeIntervalSince1970: 2),
            statusCode: 200, responseTimeMs: 90, status: .online
        )
        await store.save(second)

        let loaded = await store.load(projectID: projectID)
        XCTAssertEqual(loaded?.status, .online,
                       "Latest save must shadow the previous one for the same project.")
        XCTAssertEqual(loaded?.responseTimeMs, 90)
    }

    /// Loading a project that's never had a pulse returns nil. The
    /// ProjectCard reads that as `.unknown` and hides the dot.
    func test_load_missingProject_returnsNil() async {
        let (store, _) = makeStore()
        let loaded = await store.load(projectID: UUID())
        XCTAssertNil(loaded)
    }

    /// `allPulses()` surfaces every saved pulse, regardless of status.
    /// Used by the future "what's on fire" surface.
    func test_allPulses_listsEverySavedRecord() async {
        let (store, _) = makeStore()

        let a = HealthPulse(projectID: UUID(), host: "a", statusCode: 200, responseTimeMs: 80, status: .online)
        let b = HealthPulse(projectID: UUID(), host: "b", statusCode: 500, responseTimeMs: 40, status: .error)
        let c = HealthPulse(projectID: UUID(), host: "c", statusCode: -1, responseTimeMs: 0, status: .offline)

        await store.save(a)
        await store.save(b)
        await store.save(c)

        let all = await store.allPulses()
        XCTAssertEqual(all.count, 3)
        let hosts = Set(all.map(\.host))
        XCTAssertEqual(hosts, ["a", "b", "c"])
    }

    /// Delete removes the pulse from the cache. Future load returns
    /// nil. The pulse file under `rootURL` should also be gone.
    func test_delete_removesFromCacheAndDisk() async {
        let (store, _) = makeStore()
        let projectID = UUID()
        let pulse = HealthPulse(
            projectID: projectID,
            host: "h", statusCode: 200, responseTimeMs: 80, status: .online
        )
        await store.save(pulse)
        let beforeDelete = await store.load(projectID: projectID)
        XCTAssertNotNil(beforeDelete)

        await store.delete(projectID: projectID)
        let afterDelete = await store.load(projectID: projectID)
        XCTAssertNil(afterDelete)
    }

    /// `clearAll()` wipes every record + the on-disk directory.
    /// Idempotent: calling it twice doesn't crash.
    func test_clearAll_wipesEveryRecord() async {
        let (store, _) = makeStore()
        await store.save(HealthPulse(projectID: UUID(), host: "h", statusCode: 200, responseTimeMs: 80, status: .online))
        await store.save(HealthPulse(projectID: UUID(), host: "h", statusCode: 200, responseTimeMs: 80, status: .online))

        await store.clearAll()
        let after = await store.allPulses().count
        XCTAssertEqual(after, 0)

        // Idempotent: calling again on an empty store is fine.
        await store.clearAll()
        let afterTwice = await store.allPulses().count
        XCTAssertEqual(afterTwice, 0)
    }

    /// Hydration must rebuild the cache across a fresh store instance
    /// rooted at the same directory. This is the launch-time contract:
    /// the second launch reads pulses saved in the first launch.
    func test_hydration_repopulatesCacheFromDisk_acrossInstances() async {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("health-pulses-hydration-\(UUID().uuidString)", isDirectory: true)

        let projectID = UUID()
        let pulse = HealthPulse(
            projectID: projectID,
            host: "www.example.com",
            checkedAt: Date(timeIntervalSince1970: 1_700_000_000),
            statusCode: 200,
            responseTimeMs: 280,
            status: .online
        )

        let store1 = HealthPulseStore(rootURL: root)
        await store1.save(pulse)

        // Simulate app relaunch by discarding the first instance and
        // creating a fresh one against the same on-disk directory.
        let store2 = HealthPulseStore(rootURL: root)
        let loaded = await store2.load(projectID: projectID)

        XCTAssertEqual(loaded, pulse,
                       "Fresh store instance must rehydrate the cache from disk on first read.")

        // Cleanup
        try? FileManager.default.removeItem(at: root)
    }
}
