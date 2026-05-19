import XCTest
@testable import LinearKit

/// Locks the contract on the `LinearTeam` value type used by the
/// Settings team picker. `Identifiable` so SwiftUI ForEach lays out
/// pills without an explicit `\.self` keypath; `Equatable` so
/// `onChange(of:)` reactivity in the picker fires only on real
/// changes; `Codable` so a future cache layer (UserDefaults-pinned
/// last-known teams) drops in without re-rolling the encode side.
final class LinearTeamTests: XCTestCase {

    func testIdentifiableUsesIDField() {
        let team = LinearTeam(id: "team_abc", key: "ENG", name: "Engineering")
        XCTAssertEqual(team.id, "team_abc")
    }

    func testEquatableComparesAllThreeFields() {
        let a = LinearTeam(id: "id1", key: "ENG", name: "Engineering")
        let b = LinearTeam(id: "id1", key: "ENG", name: "Engineering")
        let differentName = LinearTeam(id: "id1", key: "ENG", name: "Engineering Beta")
        let differentKey = LinearTeam(id: "id1", key: "FOO", name: "Engineering")
        let differentID = LinearTeam(id: "id2", key: "ENG", name: "Engineering")

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, differentName)
        XCTAssertNotEqual(a, differentKey)
        XCTAssertNotEqual(a, differentID)
    }

    func testCodableRoundTripPreservesAllFields() throws {
        let original = LinearTeam(id: "team_xyz", key: "MIND", name: "MIND core")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LinearTeam.self, from: data)

        XCTAssertEqual(decoded.id, "team_xyz")
        XCTAssertEqual(decoded.key, "MIND")
        XCTAssertEqual(decoded.name, "MIND core")
        XCTAssertEqual(decoded, original)
    }
}
