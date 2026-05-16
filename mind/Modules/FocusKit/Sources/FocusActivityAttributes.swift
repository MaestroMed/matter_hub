import Foundation
import ActivityKit

/// Live Activity contract for a Deep Focus session. The fixed metadata
/// (intention + total duration) lives in the attributes; the changing
/// timer state lives in `ContentState` and is pushed via `Activity.update`.
///
/// Both halves are deliberately value types and Sendable so they cross
/// the actor isolation boundary between the app process and the widget
/// extension cleanly under Swift 6 strict concurrency.
public struct FocusActivityAttributes: ActivityAttributes, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        public enum Phase: String, Codable, Sendable, CaseIterable {
            case running
            case paused
            case completed
        }

        /// Drives the accent of the Lock Screen + Dynamic Island chrome.
        /// We keep the choice symbolic (not a SwiftUI Color) so this type
        /// stays SwiftUI-free and can be shared with anything that
        /// imports FocusKit — including pure-data clients on watchOS.
        public enum PulseColor: String, Codable, Sendable, CaseIterable {
            case lavender
            case iris
            case aqua
        }

        public var phase: Phase
        public var endDate: Date
        public var pulseColor: PulseColor

        public init(
            phase: Phase,
            endDate: Date,
            pulseColor: PulseColor = .iris
        ) {
            self.phase = phase
            self.endDate = endDate
            self.pulseColor = pulseColor
        }
    }

    public let sessionID: UUID
    public let intention: String
    public let totalDuration: TimeInterval

    public init(
        sessionID: UUID,
        intention: String,
        totalDuration: TimeInterval
    ) {
        self.sessionID = sessionID
        self.intention = intention
        self.totalDuration = totalDuration
    }
}
