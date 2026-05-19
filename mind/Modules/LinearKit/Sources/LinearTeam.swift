import Foundation

/// One Linear team as returned by the GraphQL `teams { nodes { id key name } }`
/// query. Used by the Settings team picker so the user can select which
/// team newly-created audit Quick Win issues land in.
///
/// Why three fields and no more?
/// -----------------------------
/// - `id`: opaque UUID-like string Linear requires as `teamId` on every
///   `issueCreate` mutation. The Settings picker stores this in
///   `MINDPreferences.linearDefaultTeamID`.
/// - `key`: human-readable short prefix (e.g. "ENG", "MIND") that
///   Linear surfaces in issue identifiers. Shown in the picker pill so
///   Mehdi recognises the team at a glance.
/// - `name`: full team name (e.g. "Engineering", "MIND core") for the
///   pill label.
///
/// `Identifiable` so SwiftUI ForEach lays out the pill row without a
/// `\.self` keypath ceremony, `Sendable` because the picker fetch
/// crosses the LinearClient actor boundary, `Equatable` for SwiftUI
/// `onChange(of:)` reactivity in the picker, `Codable` so a future
/// cache layer (UserDefaults-pinned last-known teams list) drops in
/// without re-rolling the encode side.
public struct LinearTeam: Identifiable, Sendable, Codable, Equatable {
    public let id: String
    public let key: String
    public let name: String

    public init(id: String, key: String, name: String) {
        self.id = id
        self.key = key
        self.name = name
    }
}
