import Foundation
import Observation
import GraphCore  // for MINDTelemetry

/// Orchestrates a digital audit run end-to-end:
///   1. probe every free public source in parallel (PageSpeed + secondary
///      findings),
///   2. hand the typed measurements to Claude for synthesis,
///   3. expose the resulting AuditReport so the SwiftUI layer can render
///      it and the caller can persist it as Nodes in the graph.
///
/// Stays a single @MainActor singleton; the network and LLM work runs
/// inside structured async children so cancellation reaches them.
@MainActor
@Observable
public final class AuditController {
    public static let shared = AuditController()

    public enum Phase: String, Sendable {
        case idle
        case probing
        case synthesizing
        case completed
        case failed
    }

    /// One identifier per network probe. AuditSheet uses these as the
    /// ordered list of rows in the running view and the retry CTA only
    /// re-runs the probes whose `probeStates` entry is `.failed`.
    /// Raw values are persistence-stable and feed MINDTelemetry events.
    public enum ProbeKind: String, CaseIterable, Sendable, Hashable {
        case pageSpeed
        case security
        case email
        case domain
        case mobile
        case schema
        case openGraph
        case crawlability
        case compliance
        case analytics
        case payment
        case cdn
        case trust

        /// French human label shown in the per-probe row. FR for
        /// user-facing strings (Mehdi convention).
        public var label: String {
            switch self {
            case .pageSpeed:    return "PageSpeed"
            case .security:     return "Sécurité"
            case .email:        return "Email DNS"
            case .domain:       return "Domaine"
            case .mobile:       return "App iOS"
            case .schema:       return "Schema.org"
            case .openGraph:    return "OpenGraph"
            case .crawlability: return "Crawlability"
            case .compliance:   return "Compliance"
            case .analytics:    return "Analytics"
            case .payment:      return "Paiement"
            case .cdn:          return "CDN"
            case .trust:        return "Trustpilot"
            }
        }

        /// SF Symbol drawn left of the row label.
        public var systemImage: String {
            switch self {
            case .pageSpeed:    return "speedometer"
            case .security:     return "lock.shield.fill"
            case .email:        return "envelope.fill"
            case .domain:       return "globe"
            case .mobile:       return "apple.logo"
            case .schema:       return "curlybraces"
            case .openGraph:    return "square.on.square.dashed"
            case .crawlability: return "magnifyingglass.circle.fill"
            case .compliance:   return "checkmark.shield.fill"
            case .analytics:    return "chart.line.uptrend.xyaxis"
            case .payment:      return "creditcard.fill"
            case .cdn:          return "cloud.fill"
            case .trust:        return "star.fill"
            }
        }
    }

    /// Per-probe lifecycle state. The view layer renders a yellow dot
    /// for `.running`, green dot for `.ok`, red dot (with the localized
    /// reason) for `.failed`.
    public enum ProbeState: Sendable, Equatable {
        case running
        case ok
        case failed(reason: String)

        public var isOK: Bool {
            if case .ok = self { return true } else { return false }
        }

        public var isFailed: Bool {
            if case .failed = self { return true } else { return false }
        }

        public var isRunning: Bool {
            if case .running = self { return true } else { return false }
        }

        public var failureReason: String? {
            if case .failed(let reason) = self { return reason } else { return nil }
        }
    }

    public private(set) var phase: Phase = .idle
    public private(set) var report: AuditReport?
    public private(set) var error: String?

    /// Per-probe state for the current run. Empty before the first run.
    /// AuditSheet reads this to render per-probe rows + decide whether
    /// to surface the "Retry failed probes" CTA.
    public private(set) var probeStates: [ProbeKind: ProbeState] = [:]

    /// v0.22 — Optional live broadcaster. When non-nil, every probe
    /// transition + the final synthesis is mirrored to disk via the
    /// `AuditLiveBroadcaster` protocol so a static HTML viewer can
    /// follow the audit in real time. Nil = legacy behaviour, zero
    /// overhead. The host App layer sets this on the singleton just
    /// before calling `run(for:)`.
    public var liveBroadcaster: AuditLiveBroadcaster?

    /// v0.23 — Optional GPT Image 2 mockup source. When non-nil and
    /// the synthesised report has at least one quick win, the
    /// controller fires a detached task after the report lands and
    /// appends the generated mockups onto `report.mockups` so the
    /// AuditSheet carousel + the portal HTML can render them. Nil =
    /// the Vision section is hidden in the UI (key not configured,
    /// or the host explicitly opted out). The host App layer sets
    /// this on the singleton before `run(for:)` based on whether
    /// `OpenAIAPIKeyStore.read()` returned a non-empty key.
    public var mockupSource: RedesignMockupSource?

    /// v0.25 — Optional ROI estimator. When non-nil and the
    /// synthesised report has at least one quick win, the
    /// controller fires a detached task after the report lands and
    /// folds the per-QW ROI estimates onto
    /// `report.quickWins[i].estimatedMonthlyRevenueImpactEUR /
    /// .confidence`. Nil = the ROI hero card + per-QW badges stay
    /// hidden (no Anthropic key, or the host explicitly opted
    /// out). Defaults to `.shared` so the AuditSheet path doesn't
    /// need to remember to wire it on every run — the network call
    /// itself soft-fails to an empty dict on a missing key.
    public var roiEstimator: ROIEstimator? = ROIEstimator.shared

    /// v0.25 — Optional client context (industry / traffic / ARPU)
    /// passed verbatim into the ROI estimator prompt. Defaults to
    /// `.unknown`, which makes the estimator fall back to industry
    /// priors. Host UI can mutate this on the singleton before
    /// `run(for:)` based on user input or persisted preferences.
    public var roiClientContext: ClientContext = .unknown

    /// Cached probe results for the current run. Retry merges new
    /// results on top of these so a re-run only touches failed probes.
    private var lastPerformance: AuditReport.PerformanceMetrics?
    private var lastFindings: AuditFindings = AuditFindings()
    private var lastClient: AuditClient?

    private var currentTask: Task<Void, Never>?
    private let synthesizer: ClaudeSynthesizer
    private let notifier: AuditNotifier

    public init(
        synthesizer: ClaudeSynthesizer? = nil,
        notifier: AuditNotifier? = nil
    ) {
        self.synthesizer = synthesizer ?? ClaudeSynthesizer()
        self.notifier = notifier ?? AuditNotifier()
    }

    public var isRunning: Bool { Self.isRunning(for: phase) }

    /// Friendly progress label for the UI; safe to bind to a Text view.
    public var progressLabel: String { Self.progressLabel(for: phase) }

    /// Pure-function view of `isRunning` so the state machine can be
    /// exercised in unit tests without needing to drive the controller
    /// through a full audit run.
    public nonisolated static func isRunning(for phase: Phase) -> Bool {
        switch phase {
        case .idle, .completed, .failed: return false
        case .probing, .synthesizing:    return true
        }
    }

    /// Pure-function view of `progressLabel` so the FR copy can be
    /// asserted in tests phase-by-phase.
    public nonisolated static func progressLabel(for phase: Phase) -> String {
        switch phase {
        case .idle:         return "Prêt à auditer"
        case .probing:      return "13 sondes en parallèle (perf, sécu, SEO, brand, infra, trust)…"
        case .synthesizing: return "Claude rédige le rapport complet…"
        case .completed:    return "Audit terminé"
        case .failed:       return "Audit en échec"
        }
    }

    /// All probes whose state is `.failed`, in declaration order. Used
    /// by the retry CTA and exposed for tests.
    public var failedProbes: [ProbeKind] {
        ProbeKind.allCases.filter { probeStates[$0]?.isFailed == true }
    }

    public var hasFailedProbes: Bool { !failedProbes.isEmpty }

    public func cancel() {
        currentTask?.cancel()
        currentTask = nil
        phase = .idle
    }

    /// Kick off a new audit run. Replaces any in-flight one. Requests
    /// notification permission on first use so the completion banner can
    /// land even if the user backgrounded the app while the audit ran.
    public func run(for client: AuditClient) {
        cancel()
        report = nil
        error = nil
        lastPerformance = nil
        lastFindings = AuditFindings()
        lastClient = client
        // Seed all probes as `.running` so the per-probe rows render
        // immediately under the spinner, even before the first probe
        // returns.
        probeStates = Dictionary(
            uniqueKeysWithValues: ProbeKind.allCases.map { ($0, .running) }
        )
        phase = .probing

        // v0.22 — Mirror the initial snapshot to the broadcaster so a
        // polling browser sees the 14 probes light up as `running`
        // immediately, before the first network call returns.
        let broadcaster = self.liveBroadcaster
        let seed = self.probeStates
        currentTask = Task { [weak self] in
            guard let self else { return }
            await self.notifier.requestPermissionIfNeeded()
            if let broadcaster {
                await broadcaster.runStarted(client: client, probeStates: seed)
            }
            await self.execute(for: client, retryOnly: nil)
        }
    }

    /// Re-run only the probes whose state is `.failed`. Succeeded
    /// results from the prior run are preserved. If everything is
    /// already green this is a no-op. Caller is AuditSheet's
    /// "Réessayer les sondes en échec" CTA — surfaced when at least
    /// one probe failed during the most recent run.
    public func retryFailedProbes() {
        guard let client = lastClient else { return }
        let failed = failedProbes
        guard !failed.isEmpty else { return }
        cancel()
        error = nil
        // Mark only the failed probes as running again; keep the
        // successful ones at `.ok` so the per-probe UI doesn't flicker
        // between green and yellow.
        for kind in failed { probeStates[kind] = .running }
        phase = .probing
        let retrySet = Set(failed)

        currentTask = Task { [weak self] in
            guard let self else { return }
            await self.execute(for: client, retryOnly: retrySet)
        }
    }

    private func execute(
        for client: AuditClient,
        retryOnly: Set<ProbeKind>?
    ) async {
        let host = client.url.host ?? client.url.absoluteString
        if retryOnly == nil {
            MINDTelemetry.info(
                "audit.start",
                data: ["host": host, "client": client.name ?? host]
            )
        } else {
            MINDTelemetry.info(
                "audit.retry",
                data: [
                    "host": host,
                    "probes": (retryOnly ?? []).map(\.rawValue).sorted().joined(separator: ","),
                ]
            )
        }
        do {
            phase = .probing
            let (performance, findings) = await runProbesInParallel(
                for: client,
                retryOnly: retryOnly
            )
            try Task.checkCancellation()

            self.lastPerformance = performance
            self.lastFindings = findings

            phase = .synthesizing
            MINDTelemetry.info("audit.synthesize.start", data: ["host": host])
            let synthesized = try await synthesizer.synthesize(
                for: client,
                performance: performance,
                findings: findings
            )
            try Task.checkCancellation()

            self.report = synthesized
            self.phase = .completed
            MINDTelemetry.info(
                "audit.completed",
                data: [
                    "host": host,
                    "overall_score": String(synthesized.scoring.overall),
                    "failed_probes": failedProbes.map(\.rawValue).joined(separator: ","),
                ]
            )
            await notifier.notifyAuditCompleted(report: synthesized)
            if let broadcaster = self.liveBroadcaster {
                await broadcaster.auditCompleted(report: synthesized)
            }
            // v0.32 — Persist the completed report to the on-disk
            // archive so the ComparisonSheet picker can surface it
            // alongside every other audit Mehdi has ever run. Fire-
            // and-forget — the archive soft-fails on disk errors
            // (the telemetry warning records the regression) and the
            // audit completion banner is never blocked on disk I/O.
            Task.detached {
                await AuditReportArchive.shared.save(synthesized)
            }
            // v0.23 — Fire-and-forget mockup generation. Doesn't block
            // the audit completion banner — the UI renders the
            // synthesised report immediately, and the Vision section
            // populates progressively as the PNGs arrive.
            if let source = self.mockupSource {
                kickOffMockupGeneration(source: source, report: synthesized)
            }
            // v0.25 — Same pattern for ROI: fire-and-forget. The
            // Quick Wins render immediately on completion; the
            // per-QW ROI badges + the hero card pop in as soon
            // as the estimator returns. Soft-fails to "no badges"
            // so a missing Anthropic key never punishes the user.
            if let estimator = self.roiEstimator {
                kickOffROIEstimation(
                    estimator: estimator,
                    context: self.roiClientContext,
                    report: synthesized
                )
            }
        } catch is CancellationError {
            self.phase = .idle
            MINDTelemetry.info("audit.cancelled", data: ["host": host])
            if let broadcaster = self.liveBroadcaster {
                await broadcaster.auditFailed(message: "Audit annulé")
            }
        } catch {
            self.error = error.localizedDescription
            self.phase = .failed
            MINDTelemetry.error(
                "audit.failed",
                data: ["host": host, "error": error.localizedDescription]
            )
            await notifier.notifyAuditFailed(
                client: client,
                message: error.localizedDescription
            )
            if let broadcaster = self.liveBroadcaster {
                await broadcaster.auditFailed(message: error.localizedDescription)
            }
        }
    }

    /// Fans out all probe calls concurrently and folds them into a
    /// PerformanceMetrics + AuditFindings pair. Every probe is allowed
    /// to soft-fail — its state flips to `.failed(reason:)` so the UI
    /// shows a red dot, but a single bad upstream never sinks the audit.
    /// On a retry (`retryOnly` non-nil), only the listed probes run;
    /// successful results from the previous run are spliced in from
    /// `lastPerformance` / `lastFindings`.
    private func runProbesInParallel(
        for client: AuditClient,
        retryOnly: Set<ProbeKind>?
    ) async -> (AuditReport.PerformanceMetrics?, AuditFindings) {
        let url = client.url
        let host = url.host(percentEncoded: false) ?? ""
        let searchName = client.name?.trimmingCharacters(in: .whitespaces) ?? hostLabel(for: host)

        func shouldRun(_ kind: ProbeKind) -> Bool {
            retryOnly?.contains(kind) ?? true
        }

        // First wave (Session 2)
        async let perf      = runProbe(.pageSpeed,    enabled: shouldRun(.pageSpeed))    { try await PageSpeedProbe.fetch(for: url) }
        async let security  = runProbe(.security,     enabled: shouldRun(.security))     { try await SecurityHeadersProbe.fetch(for: url) }
        async let email     = runProbe(.email,        enabled: shouldRun(.email))        { try await DNSProbe.fetch(for: host) }
        async let domain    = runProbe(.domain,       enabled: shouldRun(.domain))       { try await WhoisProbe.fetch(for: host) }
        async let mobile    = runProbe(.mobile,       enabled: shouldRun(.mobile))       { try await AppStoreProbe.search(name: searchName) }

        // Second wave (ULTRAPLAN BLOC B)
        async let schema       = runProbe(.schema,       enabled: shouldRun(.schema))       { try await SchemaOrgProbe.fetch(for: url) }
        async let openGraph    = runProbe(.openGraph,    enabled: shouldRun(.openGraph))    { try await OpenGraphProbe.fetch(for: url) }
        async let crawlability = runProbe(.crawlability, enabled: shouldRun(.crawlability)) { try await RobotsSitemapProbe.fetch(for: url) }
        async let compliance   = runProbe(.compliance,   enabled: shouldRun(.compliance))   { try await CookieBannerProbe.fetch(for: url) }
        async let analytics    = runProbe(.analytics,    enabled: shouldRun(.analytics))    { try await AnalyticsProbe.fetch(for: url) }
        async let payment      = runProbe(.payment,      enabled: shouldRun(.payment))      { try await PaymentProbe.fetch(for: url) }
        async let cdn          = runProbe(.cdn,          enabled: shouldRun(.cdn))          { try await CDNProbe.fetch(for: url) }
        async let trust        = runProbe(.trust,        enabled: shouldRun(.trust))        { try await TrustpilotProbe.fetch(for: url) }

        let perfValue       = await perf
        let securityValue   = await security
        let emailValue      = await email
        let domainValue     = await domain
        let mobileValue     = await mobile
        let schemaValue     = await schema
        let ogValue         = await openGraph
        let crawlValue      = await crawlability
        let complianceValue = await compliance
        let analyticsValue  = await analytics
        let paymentValue    = await payment
        let cdnValue        = await cdn
        let trustValue      = await trust

        // Splice: on a retry, an `enabled: false` probe returns nil
        // here — we keep the previous successful value instead so the
        // synthesizer still sees the full picture.
        let mergedPerf = perfValue ?? (retryOnly != nil ? lastPerformance : nil)
        let mergedFindings = AuditFindings(
            security:     securityValue   ?? (retryOnly != nil ? lastFindings.security     : nil),
            email:        emailValue      ?? (retryOnly != nil ? lastFindings.email        : nil),
            domain:       domainValue     ?? (retryOnly != nil ? lastFindings.domain       : nil),
            mobile:       mobileValue     ?? (retryOnly != nil ? lastFindings.mobile       : nil),
            schema:       schemaValue     ?? (retryOnly != nil ? lastFindings.schema       : nil),
            openGraph:    ogValue         ?? (retryOnly != nil ? lastFindings.openGraph    : nil),
            crawlability: crawlValue      ?? (retryOnly != nil ? lastFindings.crawlability : nil),
            compliance:   complianceValue ?? (retryOnly != nil ? lastFindings.compliance   : nil),
            analytics:    analyticsValue  ?? (retryOnly != nil ? lastFindings.analytics    : nil),
            payment:      paymentValue    ?? (retryOnly != nil ? lastFindings.payment      : nil),
            cdn:          cdnValue        ?? (retryOnly != nil ? lastFindings.cdn          : nil),
            trust:        trustValue      ?? (retryOnly != nil ? lastFindings.trust        : nil)
        )
        return (mergedPerf, mergedFindings)
    }

    /// Runs a single probe, recording state transitions on the MainActor.
    /// `enabled == false` is the "skip this probe" branch used by retry
    /// — the prior state (`.ok`) is preserved.
    ///
    /// v0.22 — Probe transitions also mirror to the optional
    /// `liveBroadcaster`. The duration is measured here (in ms) so the
    /// JSON snapshot can render a "PageSpeed · 312 ms" sub-label.
    private func runProbe<T: Sendable>(
        _ kind: ProbeKind,
        enabled: Bool = true,
        _ body: @Sendable @escaping () async throws -> T
    ) async -> T? {
        guard enabled else { return nil }
        let start = ContinuousClock.now
        let broadcaster = self.liveBroadcaster
        do {
            let value = try await body()
            let durationMs = Self.elapsedMs(since: start)
            await MainActor.run { self.probeStates[kind] = .ok }
            if let broadcaster {
                await broadcaster.probeStateChanged(
                    kind: kind,
                    state: .ok,
                    durationMs: durationMs
                )
            }
            return value
        } catch {
            let durationMs = Self.elapsedMs(since: start)
            let reason = error.localizedDescription
            await MainActor.run {
                self.probeStates[kind] = .failed(reason: reason)
            }
            MINDTelemetry.warning(
                "audit.probe.failed",
                data: ["probe": kind.rawValue, "reason": reason]
            )
            if let broadcaster {
                await broadcaster.probeStateChanged(
                    kind: kind,
                    state: .failed(reason: reason),
                    durationMs: durationMs
                )
            }
            return nil
        }
    }

    /// v0.23 — Kick off a detached Task that asks the configured
    /// `RedesignMockupSource` for the 3 redesign mockups, then folds
    /// them into `self.report?.mockups` so the carousel populates
    /// progressively. Soft-fails the whole batch — a missing-key
    /// throw or a network blackout simply leaves the array empty and
    /// the UI hides the section.
    private func kickOffMockupGeneration(
        source: RedesignMockupSource,
        report synthesized: AuditReport
    ) {
        let host = synthesized.client.url.host(percentEncoded: false)
            ?? synthesized.client.url.absoluteString
        let snapshot = synthesized
        Task { [weak self] in
            guard let self else { return }
            do {
                let mockups = try await source.generate(for: snapshot)
                await MainActor.run {
                    // Only fold into the live report when the user
                    // hasn't moved on to a fresh audit in the
                    // meantime. The `generatedAt` timestamp is a
                    // stable identity proxy.
                    guard let current = self.report,
                          current.generatedAt == snapshot.generatedAt
                    else { return }
                    self.report?.mockups = mockups
                }
            } catch {
                // The generator already logged the failure via its
                // own telemetry breadcrumbs; the controller only
                // records the host so a future search across runs
                // can correlate.
                MINDTelemetry.warning(
                    "redesignMockup.generation.aborted",
                    data: [
                        "host": host,
                        "reason": error.localizedDescription,
                    ]
                )
            }
        }
    }

    /// v0.25 — Kick off a detached Task that asks the configured
    /// `ROIEstimator` for per-QW ROI estimates, then folds them
    /// into `self.report?.quickWins[i]` via UUID matching. Soft-
    /// fails the whole batch — a missing-key throw or a network
    /// blackout simply leaves the QWs without ROI badges and the
    /// hero card hidden. The fresh-audit guard (compares
    /// `generatedAt`) prevents a slow-returning estimate from
    /// poisoning a more recent report.
    private func kickOffROIEstimation(
        estimator: ROIEstimator,
        context: ClientContext,
        report synthesized: AuditReport
    ) {
        let host = synthesized.client.url.host(percentEncoded: false)
            ?? synthesized.client.url.absoluteString
        let snapshot = synthesized
        Task { [weak self] in
            guard let self else { return }
            do {
                let estimates = try await estimator.estimate(
                    report: snapshot,
                    clientContext: context
                )
                guard !estimates.isEmpty else { return }
                await MainActor.run {
                    guard let current = self.report,
                          current.generatedAt == snapshot.generatedAt
                    else { return }
                    var updated = current.quickWins
                    for idx in updated.indices {
                        guard let est = estimates[updated[idx].id] else { continue }
                        updated[idx].estimatedMonthlyRevenueImpactEUR =
                            est.monthlyRevenueImpactEUR
                        updated[idx].confidence = est.confidence
                    }
                    self.report?.quickWins = updated
                }
            } catch {
                MINDTelemetry.warning(
                    "roi.estimation.failed",
                    data: [
                        "host": host,
                        "stage": "kickoff",
                        "reason": error.localizedDescription,
                    ]
                )
            }
        }
    }

    /// Wall-time elapsed since `start`, rounded to milliseconds.
    /// Pulled out so tests can assert against it without dragging in
    /// a `ContinuousClock` mock.
    private nonisolated static func elapsedMs(since start: ContinuousClock.Instant) -> Int {
        let elapsed = ContinuousClock.now - start
        return Int((elapsed.components.attoseconds / 1_000_000_000_000_000)
                   + elapsed.components.seconds * 1_000)
    }

    /// Best-effort label when the user didn't provide a name. "stripe.com"
    /// becomes "stripe", "shop.acme.co.uk" becomes "acme".
    private nonisolated func hostLabel(for host: String) -> String {
        let cleaned = host.replacingOccurrences(of: "www.", with: "")
        let parts = cleaned.split(separator: ".")
        guard parts.count >= 2 else { return cleaned }
        // For 3+ parts pick the second-to-last (handles .co.uk / .com.au).
        let candidate = parts.count >= 3
            ? String(parts[parts.count - 2])
            : String(parts[0])
        return candidate
    }
}
