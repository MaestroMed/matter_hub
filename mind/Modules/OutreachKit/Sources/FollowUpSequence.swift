import Foundation

/// v0.29 — Smart Follow-Up Sequence value types + pure builder.
///
/// After Mehdi taps "Ouvrir dans Mail" on a generated outreach variant
/// (v0.26) and flips the in-sheet "Programmer la suite (4 touches)"
/// toggle, a `FollowUpSequence` is minted, persisted via
/// `FollowUpStore`, and four local notifications are queued by
/// `FollowUpScheduler` for 9am the morning of each touch's
/// `scheduledFor`. When the user later marks the prospect "replied"
/// from `NodeDetailView` (client kind), the sequence flips to
/// `.replied` and all pending touches are cancelled.
///
/// Architecture
/// ------------
/// - `FollowUpSequence` (Codable, Equatable, Sendable) — header that
///   links a prospect Node id to a list of `FollowUpTouch` rows plus
///   the current `SequenceStatus`. Persisted as one JSON file per
///   sequence in `Documents/follow-ups/<id>.json`.
/// - `FollowUpTouch` (Identifiable Codable value) — one row in the
///   sequence: which `dayOffset` from the start date, what `channel`,
///   which `angle`, when it's scheduled to fire, current `status`,
///   and an optional pre-drafted `draftMessage` Claude pre-wrote so
///   Mehdi can ship the touch with one tap when the notification
///   wakes him.
/// - `FollowUpSequenceBuilder` (pure namespace) — turns a prospect id
///   + start date into a default-template sequence, or an arbitrary
///   custom template. The default template is the contract: Day 0
///   initial email, Day 3 LinkedIn reminder, Day 7 value-add email,
///   Day 14 break-up email.
///
/// Why value types: every field is immutable from outside (`public
/// let` or `public var` flipped from `mutating` helpers below) so the
/// store can hand a snapshot to the UI without worrying about an
/// observer mutating it under SwiftUI. The few `mutating` helpers
/// (`markTouchSent`, `markReplied`, `markPaused`, `recompute`) live
/// on the struct so callers don't have to reach into individual
/// touch arrays — keeps the invariants centralised.
///
/// Why JSON files (and not SwiftData): a sequence is a tiny piece of
/// app state that needs to survive a crash but isn't worth a
/// CloudKit-backed model migration. One file per sequence keeps
/// concurrent writes lock-free (the store's actor serialises them
/// anyway) and makes it trivial to wipe everything in
/// Settings → Danger zone.

// MARK: - Sequence value

/// One outreach follow-up sequence tied to a single prospect Node.
/// The `id` here is independent from the prospect's `Node.id` so a
/// single prospect can have a sequence history (resumed after a deal
/// closed and a later quarter re-opens the conversation).
public struct FollowUpSequence: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    /// The prospect / client Node this sequence chases. Soft link —
    /// the store does not validate that the Node still exists; if
    /// the user deletes the prospect, the sequence is reaped at the
    /// next active-cleanup pass (cf. `FollowUpStore.reapOrphans`).
    public let prospectNodeID: UUID
    public let startedAt: Date
    public var status: SequenceStatus
    public var touches: [FollowUpTouch]
    public var pausedAt: Date?
    public var pausedReason: PauseReason?

    public init(
        id: UUID = UUID(),
        prospectNodeID: UUID,
        startedAt: Date = .now,
        status: SequenceStatus = .active,
        touches: [FollowUpTouch],
        pausedAt: Date? = nil,
        pausedReason: PauseReason? = nil
    ) {
        self.id = id
        self.prospectNodeID = prospectNodeID
        self.startedAt = startedAt
        self.status = status
        self.touches = touches
        self.pausedAt = pausedAt
        self.pausedReason = pausedReason
    }

    /// The first touch the user still has to act on (pending, not
    /// sent, not skipped). Nil when every touch has been processed —
    /// in which case `recompute()` flips the status to `.completed`.
    public var nextPendingTouch: FollowUpTouch? {
        touches.first { $0.status == .pending }
    }

    /// Touches that are scheduled to fire on the day spanning `day`
    /// (in the current calendar). Used by the HomeView "Relances du
    /// jour" card to surface today's actionable rows. Skips touches
    /// already sent / skipped so a refreshed view never shows the
    /// same row twice.
    public func touchesDue(on day: Date = .now, calendar: Calendar = .current) -> [FollowUpTouch] {
        let target = calendar.startOfDay(for: day)
        return touches.filter { touch in
            guard touch.status == .pending else { return false }
            let touchDay = calendar.startOfDay(for: touch.scheduledFor)
            return touchDay == target
        }
    }

    /// Flips the touch matching `touchID` to `.sent`. Idempotent —
    /// calling twice is a no-op past the first mutation. Also
    /// triggers a `recompute()` so the sequence's overall status
    /// transitions to `.completed` once every touch is resolved.
    public mutating func markTouchSent(touchID: UUID, at when: Date = .now) {
        guard let idx = touches.firstIndex(where: { $0.id == touchID }) else { return }
        touches[idx].status = .sent
        touches[idx].sentAt = when
        recompute()
    }

    /// Flips the touch matching `touchID` to `.skipped`. Same shape
    /// as `markTouchSent`, used by the "Reporter" / "Stop" actions on
    /// the HomeView "Relances du jour" rows.
    public mutating func markTouchSkipped(touchID: UUID) {
        guard let idx = touches.firstIndex(where: { $0.id == touchID }) else { return }
        touches[idx].status = .skipped
        recompute()
    }

    /// Marks the sequence as replied: status → `.replied`, every
    /// still-pending touch is implicitly cancelled (still `.pending`
    /// in the persisted state so we can show "3/4 done, paused at
    /// replied" in the UI; the scheduler reads `status` and removes
    /// the pending notifications). `pausedAt` is set so the UI can
    /// show "Paused 2h ago" without recomputing from scratch.
    public mutating func markReplied(at when: Date = .now) {
        status = .replied
        pausedAt = when
        pausedReason = .replied
    }

    /// User-driven pause (vs `.replied`, which is data-driven). Same
    /// shape as `markReplied` but distinguishable downstream.
    public mutating func markPaused(reason: PauseReason = .userPaused, at when: Date = .now) {
        status = .paused
        pausedAt = when
        pausedReason = reason
    }

    /// Reads the touches array and bumps the sequence-level status
    /// when warranted. Specifically: if every touch is `.sent` /
    /// `.skipped`, the sequence is `.completed`. Otherwise keep the
    /// status as-is. Centralised so call sites never set
    /// `.completed` directly (only this method does).
    public mutating func recompute() {
        // Never override a terminal user state (replied / paused) —
        // a paused sequence with all touches manually marked sent is
        // still paused; the user has to un-pause it to keep going.
        guard status == .active else { return }
        let allDone = touches.allSatisfy {
            $0.status == .sent || $0.status == .skipped
        }
        if allDone {
            status = .completed
        }
    }
}

// MARK: - Touch value

/// One row in a follow-up sequence. `dayOffset` is the calendar-day
/// distance from the sequence's `startedAt`; `scheduledFor` is the
/// computed wall-clock date (start + offset, snapped to noon so the
/// scheduler can register a 9am-local trigger on that day without
/// edge-cases around DST shifts).
public struct FollowUpTouch: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    public let dayOffset: Int
    public let channel: TouchChannel
    public let angle: TouchAngle
    public var scheduledFor: Date
    public var status: TouchStatus
    public var sentAt: Date?
    public var draftMessage: String?

    public init(
        id: UUID = UUID(),
        dayOffset: Int,
        channel: TouchChannel,
        angle: TouchAngle,
        scheduledFor: Date,
        status: TouchStatus = .pending,
        sentAt: Date? = nil,
        draftMessage: String? = nil
    ) {
        self.id = id
        self.dayOffset = dayOffset
        self.channel = channel
        self.angle = angle
        self.scheduledFor = scheduledFor
        self.status = status
        self.sentAt = sentAt
        self.draftMessage = draftMessage
    }
}

// MARK: - Enums

public enum SequenceStatus: String, Sendable, Codable, CaseIterable {
    case active
    case paused
    case replied
    case completed
}

public enum PauseReason: String, Sendable, Codable, CaseIterable {
    case userPaused
    case replied
    case doNotContact
}

public enum TouchChannel: String, Sendable, Codable, CaseIterable {
    case email
    case linkedIn
}

public enum TouchAngle: String, Sendable, Codable, CaseIterable {
    case initial
    case reminder
    case valueAdd
    case breakUp
}

public enum TouchStatus: String, Sendable, Codable, CaseIterable {
    case pending
    case sent
    case skipped
}

// MARK: - Builder

/// Pure factory for `FollowUpSequence` instances. Lives in its own
/// namespace so test suites can call it without spinning up the
/// store / scheduler stack. The default template encodes the v0.29
/// contract; callers (rare) can override with a custom cadence.
public enum FollowUpSequenceBuilder {

    /// The canonical 4-touch template. Each tuple is
    /// `(dayOffset, channel, angle)`. Order matters: the builder
    /// preserves it so `nextPendingTouch` and the HomeView "step
    /// indicator" both read the sequence in chronological order.
    ///
    /// Day 0 is the initial email Mehdi already sent via the
    /// v0.26 OutreachSheet — recorded for completeness so the
    /// sequence header has a clean "1/4 done, 3/4 to go" math from
    /// the moment the toggle fires.
    public static let defaultTemplate: [(Int, TouchChannel, TouchAngle)] = [
        (0,  .email,     .initial),
        (3,  .linkedIn,  .reminder),
        (7,  .email,     .valueAdd),
        (14, .email,     .breakUp),
    ]

    /// Build a sequence for the given prospect Node id starting at
    /// `startDate`. The `template` defaults to the 4-touch canonical
    /// cadence; pass a custom array to override (tests cover both
    /// paths). The initial Day 0 touch is auto-marked `.sent` because
    /// the toggle that triggers this builder fires from the "Ouvrir
    /// dans Mail" CTA — by the time the sequence exists, the user is
    /// already sending the initial email.
    public static func build(
        prospectNodeID: UUID,
        startDate: Date = .now,
        template: [(Int, TouchChannel, TouchAngle)] = defaultTemplate,
        calendar: Calendar = .current
    ) -> FollowUpSequence {
        var calendar = calendar
        calendar.timeZone = .current

        let normalizedStart = calendar.startOfDay(for: startDate)
        let touches: [FollowUpTouch] = template.enumerated().map { _, tuple in
            let (offset, channel, angle) = tuple
            // Snap to noon on the target day so the scheduler can
            // safely register a 9am-local trigger relative to it
            // without DST edge cases (a midnight anchor would cross
            // the spring-forward / fall-back boundary unpredictably).
            let raw = calendar.date(byAdding: .day, value: offset, to: normalizedStart)
                ?? normalizedStart.addingTimeInterval(TimeInterval(offset) * 86_400)
            let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: raw) ?? raw

            // Day 0 is the initial email; the toggle fires when the
            // user is about to send it via Mail.app, so we mark it
            // sent immediately to keep the "1/4" math honest and to
            // skip queueing a redundant notification for "today".
            let preSent = offset == 0
            return FollowUpTouch(
                dayOffset: offset,
                channel: channel,
                angle: angle,
                scheduledFor: noon,
                status: preSent ? .sent : .pending,
                sentAt: preSent ? startDate : nil
            )
        }

        return FollowUpSequence(
            prospectNodeID: prospectNodeID,
            startedAt: startDate,
            status: .active,
            touches: touches
        )
    }
}
