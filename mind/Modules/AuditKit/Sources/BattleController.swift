import Foundation
import Observation
import GraphCore  // for MINDTelemetry

/// v0.24 — Audit Battle Mode.
///
/// Orchestrates a 4-way audit comparison: one "primary" client + up
/// to three competitors run concurrently inside a `TaskGroup` of
/// fresh `AuditController` instances (one per participant — the
/// shared singleton is reserved for the single-target flow so the
/// two surfaces don't fight over phase / report state).
///
/// Soft-fail per participant: a network blackout on Mollie doesn't
/// sink the battle, the UI just renders an `error` ribbon on that
/// card and the radar polygon falls back to zeros so the geometry
/// still draws.
@MainActor
@Observable
public final class BattleController {

    /// One participant in the battle. The `report` lands when the
    /// audit completes, the `error` lands when the underlying
    /// AuditController flips to `.failed`. Both stay nil while the
    /// audit is in flight, which is the cue for the UI to render
    /// the per-probe spinner row.
    public struct Participant: Identifiable, Sendable {
        public let id: UUID
        public let client: AuditClient
        public var report: AuditReport?
        public var error: String?
        public var probeStates: [AuditController.ProbeKind: AuditController.ProbeState]
        public var phase: AuditController.Phase

        public init(
            id: UUID = UUID(),
            client: AuditClient,
            report: AuditReport? = nil,
            error: String? = nil,
            probeStates: [AuditController.ProbeKind: AuditController.ProbeState] = [:],
            phase: AuditController.Phase = .idle
        ) {
            self.id = id
            self.client = client
            self.report = report
            self.error = error
            self.probeStates = probeStates
            self.phase = phase
        }

        /// True once the audit has either landed a report or
        /// definitively failed — the UI uses this to flip from the
        /// per-probe spinner to the radar polygon.
        public var isResolved: Bool {
            report != nil || error != nil
        }
    }

    public enum Phase: Sendable {
        case idle
        case running
        case completed
    }

    public private(set) var participants: [Participant] = []
    public private(set) var phase: Phase = .idle

    private var currentTask: Task<Void, Never>?

    public init() {}

    /// True when at least one participant audit is still in flight.
    public var isRunning: Bool { phase == .running }

    /// Snapshot of the current state as a `BattleReport`. Safe to
    /// read at any time — un-resolved participants simply contribute
    /// no winners on their axes.
    public var snapshot: BattleReport {
        BattleReport.derive(from: participants)
    }

    public func cancel() {
        currentTask?.cancel()
        currentTask = nil
        phase = .idle
    }

    /// Fire-and-forget telemetry hook the host App layer calls
    /// after handing a battle report off to ClientPortalKit. Lives
    /// here so the BattleController owns its full breadcrumb
    /// vocabulary (started / completed / participant.failed /
    /// exported.portal) and a future telemetry consumer can read
    /// the four events together as one funnel.
    public static func recordExportToPortal(participantCount: Int) {
        MINDTelemetry.info(
            "battle.exported.portal",
            data: ["count": String(participantCount)]
        )
    }

    /// Kick off a 4-way (or fewer) audit. Each participant gets a
    /// fresh `AuditController` so they don't trample each other's
    /// phase machinery. The controller polls each child every 200 ms
    /// to mirror probe + phase transitions into `participants` so
    /// the UI can render running spinners and the final radar
    /// without subscribing to N inner controllers individually.
    public func run(primary: AuditClient, competitors: [AuditClient]) {
        cancel()
        let allClients = [primary] + competitors
        participants = allClients.map { Participant(client: $0) }
        phase = .running

        MINDTelemetry.info(
            "battle.started",
            data: [
                "primary": primary.url.host(percentEncoded: false) ?? primary.url.absoluteString,
                "count": String(allClients.count),
            ]
        )

        currentTask = Task { [weak self] in
            guard let self else { return }
            await self.execute(clients: allClients)
        }
    }

    private func execute(clients: [AuditClient]) async {
        // Spin up one fresh AuditController per client and drive
        // them in parallel through a TaskGroup. Each child polls
        // its controller every 200 ms to mirror probe states into
        // `participants[idx]` so the BattleSheet renders progress
        // in real time without subscribing to N child observables.
        let controllers: [AuditController] = clients.map { _ in AuditController() }
        for (idx, controller) in controllers.enumerated() {
            controller.run(for: clients[idx])
        }

        await withTaskGroup(of: Void.self) { group in
            for idx in clients.indices {
                let controller = controllers[idx]
                group.addTask { [weak self] in
                    await self?.observe(controller: controller, at: idx)
                }
            }
        }

        // All children resolved (either completed or failed). Flip
        // the battle phase and emit telemetry.
        phase = .completed
        let failedCount = participants.filter { $0.error != nil }.count
        MINDTelemetry.info(
            "battle.completed",
            data: [
                "count": String(participants.count),
                "failed": String(failedCount),
            ]
        )
    }

    /// Poll a single child controller until it lands in a terminal
    /// phase (`.completed` or `.failed`). Cancellation is honoured —
    /// the parent cancel() invalidates the Task and the controllers
    /// stop on their next cancellation check.
    private func observe(controller: AuditController, at idx: Int) async {
        // Best-effort polling: 200 ms is brisk enough to feel live
        // but cheap enough to avoid hammering the main actor with
        // hundreds of view updates per second.
        while !Task.isCancelled {
            let phase = controller.phase
            let states = controller.probeStates
            let report = controller.report
            let errorMessage = controller.error

            // Mirror into the participant slot. Guard the index in
            // case `cancel()` rebuilt `participants` mid-flight.
            if idx < participants.count {
                participants[idx].phase = phase
                participants[idx].probeStates = states
                participants[idx].report = report
                participants[idx].error = errorMessage
            }

            switch phase {
            case .completed, .failed:
                // Final mirror + bail. Soft-fail telemetry so the
                // BattleSheet error ribbon has a paper trail.
                if phase == .failed, idx < participants.count {
                    MINDTelemetry.warning(
                        "battle.participant.failed",
                        data: [
                            "host": participants[idx].client.url.host(percentEncoded: false)
                                ?? participants[idx].client.url.absoluteString,
                            "error": errorMessage ?? "unknown",
                        ]
                    )
                }
                return
            case .idle, .probing, .synthesizing:
                break
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }
}

// MARK: - BattleReport

/// Pure derivation of who wins on each metric. Read directly from
/// `BattleController.snapshot` or built standalone in tests via
/// `derive(from:)`.
public struct BattleReport: Sendable {

    /// The 6 comparison axes — same set as `AuditReport.Scoring`.
    public enum Metric: String, Sendable, CaseIterable, Hashable {
        case overall
        case performance
        case seo
        case security
        case brand
        case mobile

        /// French human label used by the BattleSheet podium row.
        public var label: String {
            switch self {
            case .overall:     return "Global"
            case .performance: return "Performance"
            case .seo:         return "SEO"
            case .security:    return "Sécurité"
            case .brand:       return "Brand"
            case .mobile:      return "Mobile"
            }
        }

        /// Localizable.xcstrings key for the FR/EN copy.
        public var stringKey: String {
            "battle.metric.\(rawValue)"
        }
    }

    public let participants: [BattleController.Participant]

    /// Per-metric winner (`AuditClient`). Missing entries mean
    /// nobody scored above zero on that axis or every participant
    /// failed — both render as an empty podium slot in the UI.
    public let winners: [Metric: AuditClient]

    public init(
        participants: [BattleController.Participant],
        winners: [Metric: AuditClient]
    ) {
        self.participants = participants
        self.winners = winners
    }

    /// Pure derivation entry-point. Given a list of participants,
    /// returns a `BattleReport` with the per-metric winner table.
    ///
    /// Tie-breaking
    /// ------------
    /// Ties are broken deterministically by participant order — the
    /// first one in the input list wins the metric. That mirrors
    /// what the user sees on screen (primary first, competitors in
    /// the order they typed them) so the badge lands where they
    /// expect.
    ///
    /// All-zero axes
    /// -------------
    /// If every resolved participant scored 0 on a metric, the
    /// metric is omitted from `winners` (no podium badge rendered).
    /// Unresolved participants are excluded from the comparison so
    /// a failed audit can't accidentally win an axis.
    public static func derive(
        from participants: [BattleController.Participant]
    ) -> BattleReport {
        var winners: [Metric: AuditClient] = [:]
        for metric in Metric.allCases {
            var bestScore = 0
            var bestClient: AuditClient?
            for participant in participants {
                guard let report = participant.report else { continue }
                let score = scoreValue(metric, in: report.scoring)
                if score > bestScore {
                    bestScore = score
                    bestClient = participant.client
                }
            }
            if let bestClient {
                winners[metric] = bestClient
            }
        }
        return BattleReport(participants: participants, winners: winners)
    }

    /// Extract a single metric value from a `Scoring`. Pure
    /// function exposed for the radar chart (UI) + tests.
    public static func scoreValue(
        _ metric: Metric,
        in scoring: AuditReport.Scoring
    ) -> Int {
        switch metric {
        case .overall:     return scoring.overall
        case .performance: return scoring.performance
        case .seo:         return scoring.seo
        case .security:    return scoring.security
        case .brand:       return scoring.brand
        case .mobile:      return scoring.mobile
        }
    }
}
