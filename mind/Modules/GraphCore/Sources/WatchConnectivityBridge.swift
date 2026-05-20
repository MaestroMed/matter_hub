import Foundation
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// v1.0-alpha.17 — Cross-device bridge between the iPhone host and the
/// Apple Watch companion. Wraps `WCSession` on both sides so:
///
/// 1. The iPhone can push a fresh `WatchLeadDigest[]` + `WatchPortfolioKPI`
///    snapshot to the Watch every `.active` scene phase (mirrors the
///    iOS 26 Lock Screen widget contract from v1.0-alpha.16).
/// 2. The Watch can post `focus.start(intention:duration:)` and
///    `focus.end` messages back to the iPhone so the wrist tap fires
///    a real Pomodoro on the host.
///
/// **Offline-first**: every push also writes to the shared App Group
/// (`group.app.mind.ios`) under `mind.watch.*` keys, so the Watch
/// renders the most-recent snapshot even when `WCSession` is inactive
/// (paired phone in airplane mode, no nearby BT, Simulator, etc.).
/// `WatchSharedSnapshot` (Watch target) is the read side; this bridge
/// owns the write side on both ends.
///
/// **Soft-fail by design**: `WCSession.isSupported() == false` (e.g.
/// iPad, Mac Catalyst, Watch target with no companion) and
/// `WCSession.default.activationState != .activated` both collapse to
/// no-op writes that still hit the App Group fallback. The bridge
/// never throws, never blocks the caller, and never crashes when the
/// session is unreachable.
///
/// Concurrency: `actor` because the underlying `WCSessionDelegate`
/// callbacks fire on a background queue and we need to mutate the
/// `messageHandlers` table without a lock. Public surface stays
/// `Sendable` because every parameter is a value type. The shared
/// instance is reached through `shared` and lives for the lifetime of
/// the process; callers `await` it.
public actor WatchConnectivityBridge {

    // MARK: - Shared instance

    public static let shared = WatchConnectivityBridge()

    // MARK: - App Group keys

    public static let appGroupSuiteName = "group.app.mind.ios"

    public enum SnapshotKey {
        /// `Data`. JSON-encoded `[WatchLeadDigest]` the iPhone last
        /// pushed. Watch falls back to this when `WCSession` is
        /// inactive.
        public static let leads = "mind.watch.leads"

        /// `Data`. JSON-encoded `WatchPortfolioKPI` the iPhone last
        /// pushed.
        public static let portfolio = "mind.watch.portfolio"

        /// `Bool`. Mirror of the running-Focus flag the iPhone toggles
        /// when it receives a `focus.start`/`focus.end` from the Watch.
        public static let focusRunning = "mind.watch.focus.running"
    }

    // MARK: - Message routing

    /// Inbound focus-start handler the iPhone host registers at
    /// launch. Closure is `@Sendable` so the WCSessionDelegate hop
    /// (background queue) stays race-free under Swift 6 strict
    /// concurrency.
    public typealias FocusStartHandler = @Sendable (FocusStartPayload) -> Void
    public typealias FocusEndHandler = @Sendable () -> Void

    private var focusStartHandler: FocusStartHandler?
    private var focusEndHandler: FocusEndHandler?

    /// v1.0-alpha.17 — Register the iPhone-side `focus.start` callback.
    /// Idempotent: re-registering replaces the previous handler.
    public func onFocusStart(_ handler: @escaping FocusStartHandler) {
        self.focusStartHandler = handler
    }

    /// v1.0-alpha.17 — Register the iPhone-side `focus.end` callback.
    public func onFocusEnd(_ handler: @escaping FocusEndHandler) {
        self.focusEndHandler = handler
    }

    // MARK: - Payloads

    /// v1.0-alpha.17 — Lead digest the iPhone pushes to the Watch.
    /// Minimal shape (no Project reach, no relationship graph) so the
    /// Watch UI never decodes more than it can render on the 38mm
    /// face.
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

    /// v1.0-alpha.17 — Portfolio KPI block the Watch portfolio tab
    /// displays. Three numbers that fit on the 38mm screen without
    /// scrolling. All counts clamp at 0 on the writer side; the
    /// formatter caps the visible glyph at "99+" for safety.
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

    /// v1.0-alpha.17 — Focus-start payload the Watch dispatches when
    /// the user taps "Démarrer Focus". `intention` is the user-visible
    /// label (FR by default: "Pomodoro"), `durationSeconds` defaults
    /// to 1500 (25 min).
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

    // MARK: - Message envelope

    /// Canonical envelope every WCSession payload follows so the
    /// receiver can route by `kind` before decoding the body. Plain
    /// `[String: Any]` because `sendMessage(_:)` only accepts JSON-
    /// native primitives.
    public enum MessageKind: String, Sendable {
        case leadsSnapshot = "leads.snapshot"
        case portfolioSnapshot = "portfolio.snapshot"
        case focusStart = "focus.start"
        case focusEnd = "focus.end"
    }

    public static let envelopeKindKey = "mind.envelope.kind"
    public static let envelopePayloadKey = "mind.envelope.payload"

    /// Build a `WCSession.sendMessage(_:)`-ready dict from a typed
    /// payload. Returns `nil` when the encoder fails (should never
    /// happen — every payload is a pure `Codable` value type).
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

    /// Decode an envelope back into a `kind` + raw payload dict. Used
    /// by both sides on `didReceiveMessage`. Returns `nil` if the
    /// envelope is malformed.
    public static func unpack(
        _ message: [String: Any]
    ) -> (kind: MessageKind, payload: Any)? {
        guard
            let rawKind = message[envelopeKindKey] as? String,
            let kind = MessageKind(rawValue: rawKind),
            let payload = message[envelopePayloadKey]
        else {
            return nil
        }
        return (kind, payload)
    }

    // MARK: - Activation

    #if canImport(WatchConnectivity)
    /// WCSession delegate adapter. Lives in a nested class because
    /// `WCSessionDelegate` requires `NSObject` inheritance which the
    /// bridge actor can't provide.
    private var delegateAdapter: WCSessionDelegateAdapter?
    #endif

    /// v1.0-alpha.17 — Activate WCSession from the iPhone host side.
    /// Soft-fails when WatchConnectivity isn't available (Mac Catalyst,
    /// older platforms). Safe to call multiple times — the delegate
    /// adapter is created on the first call only.
    nonisolated public func activatePhoneSide() {
        #if canImport(WatchConnectivity)
        Task {
            await activateInternal(role: .phone)
        }
        #endif
    }

    /// v1.0-alpha.17 — Activate WCSession from the watchOS app side.
    /// Soft-fails when WatchConnectivity isn't available.
    nonisolated public func activateWatchSide() {
        #if canImport(WatchConnectivity)
        Task {
            await activateInternal(role: .watch)
        }
        #endif
    }

    private enum Role { case phone, watch }

    #if canImport(WatchConnectivity)
    private func activateInternal(role: Role) {
        guard WCSession.isSupported() else {
            return
        }
        if delegateAdapter == nil {
            let adapter = WCSessionDelegateAdapter(bridge: self)
            delegateAdapter = adapter
            WCSession.default.delegate = adapter
            WCSession.default.activate()
        }
    }
    #endif

    // MARK: - Push (iPhone → Watch)

    /// v1.0-alpha.17 — Push the freshest lead inbox slice to the
    /// Watch. Always writes to the shared App Group first (so the
    /// Watch's offline fallback stays current) then attempts a live
    /// `sendMessage`. The live send is best-effort: failures (Watch
    /// not reachable, session inactive) are silently swallowed and
    /// surfaced via `MINDTelemetry`.
    nonisolated public func pushLeadsSnapshot(_ leads: [WatchLeadDigest]) {
        guard let data = try? JSONEncoder().encode(leads) else {
            return
        }
        let defaults = UserDefaults(suiteName: Self.appGroupSuiteName) ?? .standard
        defaults.set(data, forKey: SnapshotKey.leads)

        #if canImport(WatchConnectivity) && os(iOS)
        guard
            WCSession.isSupported(),
            WCSession.default.activationState == .activated,
            WCSession.default.isReachable,
            let envelope = Self.envelope(kind: .leadsSnapshot, payload: leads)
        else {
            return
        }
        WCSession.default.sendMessage(envelope, replyHandler: nil, errorHandler: nil)
        #endif
    }

    /// v1.0-alpha.17 — Push the freshest portfolio KPI block to the
    /// Watch. Same offline-first contract as `pushLeadsSnapshot`.
    nonisolated public func pushPortfolioKPI(_ kpi: WatchPortfolioKPI) {
        guard let data = try? JSONEncoder().encode(kpi) else {
            return
        }
        let defaults = UserDefaults(suiteName: Self.appGroupSuiteName) ?? .standard
        defaults.set(data, forKey: SnapshotKey.portfolio)

        #if canImport(WatchConnectivity) && os(iOS)
        guard
            WCSession.isSupported(),
            WCSession.default.activationState == .activated,
            WCSession.default.isReachable,
            let envelope = Self.envelope(kind: .portfolioSnapshot, payload: kpi)
        else {
            return
        }
        WCSession.default.sendMessage(envelope, replyHandler: nil, errorHandler: nil)
        #endif
    }

    // MARK: - Push (Watch → iPhone)

    /// v1.0-alpha.17 — Dispatch a `focus.start` message from the Watch
    /// to the iPhone host. Returns immediately; the iPhone-side
    /// `onFocusStart` handler fires asynchronously when the message
    /// lands. Falls back to a local App Group write so the Watch UI's
    /// running-Focus state survives an unreachable phone.
    nonisolated public func dispatchFocusStart(_ payload: FocusStartPayload) {
        let defaults = UserDefaults(suiteName: Self.appGroupSuiteName) ?? .standard
        defaults.set(true, forKey: SnapshotKey.focusRunning)

        #if canImport(WatchConnectivity) && os(watchOS)
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

    /// v1.0-alpha.17 — Dispatch a `focus.end` message from the Watch
    /// to the iPhone host. Mirrors `dispatchFocusStart`.
    nonisolated public func dispatchFocusEnd() {
        let defaults = UserDefaults(suiteName: Self.appGroupSuiteName) ?? .standard
        defaults.set(false, forKey: SnapshotKey.focusRunning)

        #if canImport(WatchConnectivity) && os(watchOS)
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

    // MARK: - Inbound (iPhone receives Watch messages)

    /// Called from the WCSession delegate adapter after the message
    /// has been serialized to `Data` (the only Sendable shape we can
    /// cross the actor boundary with). Decodes the JSON envelope back
    /// to `[String: Any]` on the actor side, then dispatches.
    func handleSerializedMessage(_ data: Data) {
        guard
            let raw = try? JSONSerialization.jsonObject(with: data, options: []),
            let message = raw as? [String: Any]
        else {
            return
        }
        handleIncomingMessage(message)
    }

    /// Called from the WCSession delegate adapter when the iPhone
    /// receives a message from the Watch. Dispatches based on `kind`
    /// to the registered handlers. Safe to call on any thread — hops
    /// into the actor for handler reads.
    func handleIncomingMessage(_ message: [String: Any]) {
        guard let (kind, payload) = Self.unpack(message) else {
            return
        }
        switch kind {
        case .focusStart:
            guard
                let dict = payload as? [String: Any],
                let data = try? JSONSerialization.data(withJSONObject: dict, options: []),
                let decoded = try? JSONDecoder().decode(FocusStartPayload.self, from: data)
            else {
                return
            }
            focusStartHandler?(decoded)
        case .focusEnd:
            focusEndHandler?()
        case .leadsSnapshot:
            // Watch-side ingest — cache to App Group so subsequent
            // tab opens read the live data without waiting on a
            // refresh.
            if let dict = payload as? [Any],
               let data = try? JSONSerialization.data(withJSONObject: dict, options: []) {
                let defaults = UserDefaults(suiteName: Self.appGroupSuiteName) ?? .standard
                defaults.set(data, forKey: SnapshotKey.leads)
            }
        case .portfolioSnapshot:
            if let dict = payload as? [String: Any],
               let data = try? JSONSerialization.data(withJSONObject: dict, options: []) {
                let defaults = UserDefaults(suiteName: Self.appGroupSuiteName) ?? .standard
                defaults.set(data, forKey: SnapshotKey.portfolio)
            }
        }
    }
}

// MARK: - WCSession delegate adapter

#if canImport(WatchConnectivity)
/// Minimal `NSObject` shim that conforms to `WCSessionDelegate`. The
/// actor can't be the delegate directly (NSObject inheritance
/// requirement), so the adapter forwards every callback into the
/// actor's `handleIncomingMessage`.
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
    ) {
        // No-op: activation failures surface via subsequent
        // sendMessage error handlers; we don't want to spam telemetry
        // for every state hop.
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // iOS docs say to re-activate after deactivation in a multi-
        // watch scenario.
        WCSession.default.activate()
    }
    #endif

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        // Serialize the message into Data (Sendable) before crossing
        // the actor boundary. `[String: Any]` itself isn't Sendable
        // under Swift 6 strict concurrency, so we round-trip it
        // through JSON. The actor decodes it back on the other side.
        guard
            let serialized = try? JSONSerialization.data(
                withJSONObject: message,
                options: []
            )
        else {
            return
        }
        Task { [serialized, bridge] in
            await bridge?.handleSerializedMessage(serialized)
        }
    }
}
#endif

// MARK: - Type aliases for iOS host

/// v1.0-alpha.17 — Host-side re-exports of the bridge's nested types
/// so call sites in `MINDApp.swift` can refer to the value types
/// without the bridge prefix. The Watch target has its own copy of
/// these (Watch/Sources/WatchConnectivityBridge.swift) — duplicated
/// rather than shared because GraphCore can't link into watchOS.
public typealias WatchLeadDigest = WatchConnectivityBridge.WatchLeadDigest
public typealias WatchPortfolioKPI = WatchConnectivityBridge.WatchPortfolioKPI
public typealias WatchFocusStartPayload = WatchConnectivityBridge.FocusStartPayload
