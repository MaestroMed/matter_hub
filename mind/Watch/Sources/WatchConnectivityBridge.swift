import Foundation
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// v1.0-alpha.17 — Watch-side mirror of the iPhone host's
/// `WatchConnectivityBridge` (lives in `Modules/GraphCore/Sources/`).
/// The Watch target can't link GraphCore (CloudKit + SwiftData reach
/// don't make sense on watchOS) so the bridge is duplicated here with
/// the same envelope shape. Tests on the iPhone side
/// (`WatchConnectivityBridgeTests`) pin the envelope contract both
/// targets follow.
///
/// Same offline-first contract as the host: every dispatch writes to
/// the shared App Group (`group.app.mind.ios`) first so the watch UI
/// updates immediately, then attempts a best-effort `WCSession`
/// message.
public actor WatchConnectivityBridge {

    public static let shared = WatchConnectivityBridge()

    public static let appGroupSuiteName = "group.app.mind.ios"

    public enum SnapshotKey {
        public static let leads = "mind.watch.leads"
        public static let portfolio = "mind.watch.portfolio"
        public static let focusRunning = "mind.watch.focus.running"
    }

    public struct WatchLeadDigest: Codable, Sendable, Equatable, Identifiable {
        public let id: UUID
        public let contactName: String
        public let messagePreview: String
        public let receivedAtMillis: Int64

        public init(
            id: UUID,
            contactName: String,
            messagePreview: String,
            receivedAtMillis: Int64
        ) {
            self.id = id
            self.contactName = contactName
            self.messagePreview = messagePreview
            self.receivedAtMillis = receivedAtMillis
        }
    }

    public struct WatchPortfolioKPI: Codable, Sendable, Equatable {
        public let leadsToday: Int
        public let mrrEUR: Int
        public let buildErrors: Int

        public init(leadsToday: Int, mrrEUR: Int, buildErrors: Int) {
            self.leadsToday = leadsToday
            self.mrrEUR = mrrEUR
            self.buildErrors = buildErrors
        }

        public static let empty = WatchPortfolioKPI(
            leadsToday: 0,
            mrrEUR: 0,
            buildErrors: 0
        )
    }

    public struct FocusStartPayload: Codable, Sendable, Equatable {
        public let intention: String
        public let durationSeconds: Int

        public init(intention: String, durationSeconds: Int) {
            self.intention = intention
            self.durationSeconds = durationSeconds
        }

        public static let pomodoroDefault = FocusStartPayload(
            intention: "Pomodoro",
            durationSeconds: 1_500
        )
    }

    public enum MessageKind: String, Sendable {
        case leadsSnapshot = "leads.snapshot"
        case portfolioSnapshot = "portfolio.snapshot"
        case focusStart = "focus.start"
        case focusEnd = "focus.end"
    }

    public static let envelopeKindKey = "mind.envelope.kind"
    public static let envelopePayloadKey = "mind.envelope.payload"

    public static func envelope<T: Encodable>(
        kind: MessageKind,
        payload: T
    ) -> [String: Any]? {
        guard
            let data = try? JSONEncoder().encode(payload),
            let json = try? JSONSerialization.jsonObject(with: data, options: [])
        else {
            return nil
        }
        return [
            envelopeKindKey: kind.rawValue,
            envelopePayloadKey: json,
        ]
    }

    #if canImport(WatchConnectivity)
    private var delegateAdapter: WCSessionDelegateAdapter?
    #endif

    nonisolated public func activateWatchSide() {
        #if canImport(WatchConnectivity)
        Task {
            await activateInternal()
        }
        #endif
    }

    #if canImport(WatchConnectivity)
    private func activateInternal() {
        guard WCSession.isSupported() else { return }
        if delegateAdapter == nil {
            let adapter = WCSessionDelegateAdapter(bridge: self)
            delegateAdapter = adapter
            WCSession.default.delegate = adapter
            WCSession.default.activate()
        }
    }
    #endif

    nonisolated public func dispatchFocusStart(_ payload: FocusStartPayload) {
        let defaults = UserDefaults(suiteName: Self.appGroupSuiteName) ?? .standard
        defaults.set(true, forKey: SnapshotKey.focusRunning)

        #if canImport(WatchConnectivity)
        guard
            WCSession.isSupported(),
            WCSession.default.activationState == .activated,
            let envelope = Self.envelope(kind: .focusStart, payload: payload)
        else {
            return
        }
        WCSession.default.sendMessage(envelope, replyHandler: nil, errorHandler: nil)
        #endif
    }

    nonisolated public func dispatchFocusEnd() {
        let defaults = UserDefaults(suiteName: Self.appGroupSuiteName) ?? .standard
        defaults.set(false, forKey: SnapshotKey.focusRunning)

        #if canImport(WatchConnectivity)
        guard
            WCSession.isSupported(),
            WCSession.default.activationState == .activated
        else {
            return
        }
        let envelope: [String: Any] = [
            Self.envelopeKindKey: MessageKind.focusEnd.rawValue,
            Self.envelopePayloadKey: [String: Any](),
        ]
        WCSession.default.sendMessage(envelope, replyHandler: nil, errorHandler: nil)
        #endif
    }

    /// Watch-side ingest of a serialized message from the iPhone.
    /// Decodes the JSON back into the dict shape on the actor side
    /// (the `[String: Any]` type isn't Sendable, so the delegate
    /// adapter passes us `Data` instead).
    func ingestSerialized(_ data: Data) {
        guard
            let raw = try? JSONSerialization.jsonObject(with: data, options: []),
            let message = raw as? [String: Any]
        else {
            return
        }
        ingest(message)
    }

    /// Watch-side ingest of a `leads.snapshot` / `portfolio.snapshot`
    /// payload from the iPhone. Caches the JSON in the App Group so
    /// the next tab open reads the live values.
    func ingest(_ message: [String: Any]) {
        guard
            let rawKind = message[Self.envelopeKindKey] as? String,
            let kind = MessageKind(rawValue: rawKind),
            let payload = message[Self.envelopePayloadKey]
        else { return }

        let defaults = UserDefaults(suiteName: Self.appGroupSuiteName) ?? .standard
        switch kind {
        case .leadsSnapshot:
            if let array = payload as? [Any],
               let data = try? JSONSerialization.data(withJSONObject: array, options: []) {
                defaults.set(data, forKey: SnapshotKey.leads)
            }
        case .portfolioSnapshot:
            if let dict = payload as? [String: Any],
               let data = try? JSONSerialization.data(withJSONObject: dict, options: []) {
                defaults.set(data, forKey: SnapshotKey.portfolio)
            }
        case .focusStart, .focusEnd:
            // Watch never receives these (it dispatches them).
            break
        }
    }
}

#if canImport(WatchConnectivity)
final class WCSessionDelegateAdapter: NSObject, WCSessionDelegate, @unchecked Sendable {

    private weak var bridge: WatchConnectivityBridge?

    init(bridge: WatchConnectivityBridge) {
        self.bridge = bridge
        super.init()
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        guard
            let serialized = try? JSONSerialization.data(
                withJSONObject: message,
                options: []
            )
        else {
            return
        }
        Task { [serialized, bridge] in
            await bridge?.ingestSerialized(serialized)
        }
    }
}
#endif

/// v1.0-alpha.17 — Watch-target type aliases so the views can refer
/// to the value types without the bridge prefix.
public typealias WatchLeadDigest = WatchConnectivityBridge.WatchLeadDigest
public typealias WatchPortfolioKPI = WatchConnectivityBridge.WatchPortfolioKPI
public typealias WatchFocusStartPayload = WatchConnectivityBridge.FocusStartPayload
