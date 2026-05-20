import XCTest
@testable import SwarmKit

/// v1.0-alpha.7 — Locks the `SEOSwarmStore` actor's JSON persistence.
/// Every test runs against a hermetic temp directory so the simulator's
/// own `Documents/seo-swarm-jobs/` is never touched between runs.
final class SEOSwarmStoreTests: XCTestCase {

    // MARK: - Helpers

    /// Allocate a unique temp directory per test so concurrent runs
    /// never race on the same files.
    private func tempStoreRoot() -> URL {
        let root = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("mind-swarm-store-tests-\(UUID().uuidString)", isDirectory: true)
        return root
    }

    private func sampleJob(_ id: UUID = UUID()) -> SEOSwarmJob {
        SEOSwarmJob(
            id: id,
            projectID: UUID(),
            projectName: "AZ Construction",
            projectHost: "www.azconstruction.fr",
            services: ["verriere", "escalier"],
            zones: [
                SwarmZone(slug: "puteaux", displayName: "Puteaux", departmentCode: "92", population: 45_000),
                SwarmZone(slug: "neuilly-sur-seine", displayName: "Neuilly-sur-Seine", departmentCode: "92", population: 62_600),
            ]
        )
    }

    // MARK: - Round trip

    /// Save then load reproduces the same job byte-for-byte.
    func test_store_savesAndLoadsAJob() async {
        let root = tempStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SEOSwarmStore(rootURL: root)
        let job = sampleJob()
        await store.save(job)
        let loaded = await store.load(job.id)
        XCTAssertEqual(loaded, job)
    }

    /// `allJobs()` returns every saved job (any order) so the
    /// future Cockpit history view can list them all.
    func test_store_listsAllJobs() async {
        let root = tempStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SEOSwarmStore(rootURL: root)
        let jobA = sampleJob()
        let jobB = sampleJob()
        let jobC = sampleJob()
        await store.save(jobA)
        await store.save(jobB)
        await store.save(jobC)
        let listed = await store.allJobs()
        let listedIDs = Set(listed.map(\.id))
        XCTAssertEqual(listedIDs, Set([jobA.id, jobB.id, jobC.id]))
    }

    /// Delete removes the file + cache entry; subsequent `load`
    /// returns nil.
    func test_store_deleteRemovesJob() async {
        let root = tempStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SEOSwarmStore(rootURL: root)
        let job = sampleJob()
        await store.save(job)
        await store.delete(job.id)
        let loaded = await store.load(job.id)
        XCTAssertNil(loaded)
    }

    /// `load` on a never-saved id returns nil rather than throwing,
    /// so the UI can skip a missing-file gracefully.
    func test_store_loadMissingJobReturnsNil() async {
        let root = tempStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SEOSwarmStore(rootURL: root)
        let loaded = await store.load(UUID())
        XCTAssertNil(loaded)
    }
}
