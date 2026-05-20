import XCTest
import Foundation
@testable import CalendarKit
@testable import GraphCore

/// v0.28 — Locks the pure surface of `MeetingBriefBuilder`. Every
/// rendered string + every fallback branch on the Discovery Call
/// Prep Dossier flows out of these functions, so a regression here
/// either ships the wrong opening line on tomorrow's call or leaves
/// the questions section showing 4 questions instead of 5.
///
/// Strategy: build small in-memory `Node` + `CalendarEvent` value
/// types, run the builder, assert on the returned shape. No
/// SwiftData container needed — `Node` is the model type but we
/// instantiate it directly with its public init, which doesn't
/// touch the SwiftData stack.
final class MeetingBriefBuilderTests: XCTestCase {

    // MARK: - Fixtures

    private func makeEvent(
        id: String = "evt-\(UUID().uuidString)",
        title: String = "Discovery Stripe",
        attendees: [String] = ["Jane Doe"],
        emails: [String] = ["jane.doe@stripe.com"],
        startOffsetHours: Double = 24
    ) -> CalendarEvent {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
            .addingTimeInterval(startOffsetHours * 3600)
        return CalendarEvent(
            id: id,
            title: title,
            startDate: start,
            endDate: start.addingTimeInterval(3600),
            location: "Visio",
            attendees: attendees,
            attendeeEmails: emails,
            notes: nil
        )
    }

    private func makeClient(
        name: String,
        domain: String,
        tags: [String] = []
    ) -> Node {
        let node = Node(
            kind: .client,
            title: name,
            content: "https://\(domain)",
            tags: tags,
            sourceURL: "https://\(domain)"
        )
        return node
    }

    // MARK: - detectClient

    /// Matches by email domain regardless of subdomain on the client
    /// URL. `john@stripe.com` ↔ `https://dashboard.stripe.com`.
    func test_detectClient_matchesByEmailDomain() {
        let stripe = makeClient(name: "Stripe", domain: "stripe.com")
        let acme   = makeClient(name: "Acme", domain: "acme.io")
        let event  = makeEvent(emails: ["jane.doe@dashboard.stripe.com"])
        let match  = MeetingBriefBuilder.detectClient(in: event, from: [acme, stripe])
        XCTAssertNotNil(match)
        XCTAssertEqual(match?.title, "Stripe",
                       "Email domain should match the client URL ignoring subdomain")
    }

    /// When several clients share the same root domain (rare but
    /// possible after a fork / acquisition), the first occurrence in
    /// the input array wins. Determinism is the contract.
    func test_detectClient_returnsFirstMatchDeterministically() {
        let first  = makeClient(name: "Stripe (legacy)", domain: "stripe.com")
        let second = makeClient(name: "Stripe (new)",    domain: "stripe.com")
        let event  = makeEvent(emails: ["mehdi@stripe.com"])
        let match  = MeetingBriefBuilder.detectClient(in: event, from: [first, second])
        XCTAssertEqual(match?.title, "Stripe (legacy)")
    }

    /// No attendee email → no detection, even when the title hints at
    /// the brand. We never want to false-positive on the title alone.
    func test_detectClient_noAttendees_returnsNil() {
        let stripe = makeClient(name: "Stripe", domain: "stripe.com")
        let event  = makeEvent(
            title: "Internal review Stripe",
            attendees: [],
            emails: []
        )
        XCTAssertNil(MeetingBriefBuilder.detectClient(in: event, from: [stripe]))
    }

    /// Empty client list → nil regardless of what attendees look like.
    func test_detectClient_noClients_returnsNil() {
        let event = makeEvent(emails: ["jane@stripe.com"])
        XCTAssertNil(MeetingBriefBuilder.detectClient(in: event, from: []))
    }

    // MARK: - draftDiscoveryQuestions

    /// Always returns exactly 5 questions — the sheet header claims
    /// "Questions discovery (5)", so the contract has to hold even
    /// when the heuristic falls back to the generic core.
    func test_draftDiscoveryQuestions_returnsExactlyFive_genericPath() {
        let event = makeEvent(emails: ["mehdi@example.com"])
        let questions = MeetingBriefBuilder.draftDiscoveryQuestions(for: nil, event: event)
        XCTAssertEqual(questions.count, 5)
        for q in questions {
            XCTAssertFalse(q.isEmpty, "Every question must carry text")
        }
    }

    /// Audit `security:low` tag → at least one of the 5 questions
    /// must ask about SSL / security headers. Bias surfaces first.
    func test_draftDiscoveryQuestions_securityLow_includesSecurityQuestion() {
        let stripe = makeClient(
            name: "Stripe",
            domain: "stripe.com",
            tags: ["security:low"]
        )
        let event = makeEvent(emails: ["jane@stripe.com"])
        let questions = MeetingBriefBuilder.draftDiscoveryQuestions(for: stripe, event: event)
        XCTAssertEqual(questions.count, 5)
        XCTAssertTrue(
            questions.contains { $0.contains("SSL") || $0.contains("sécurité") },
            "Security question must surface when client tagged security:low"
        )
    }

    /// No matching client and no audit tags → 5 generic French
    /// questions, every one of them ending with a question mark.
    func test_draftDiscoveryQuestions_noClient_returnsFiveGenericFrenchQuestions() {
        let event = makeEvent(emails: ["x@y.com"])
        let questions = MeetingBriefBuilder.draftDiscoveryQuestions(for: nil, event: event)
        XCTAssertEqual(questions.count, 5)
        for q in questions {
            XCTAssertTrue(q.hasSuffix("?"), "Generic discovery questions end with a '?'")
        }
    }

    // MARK: - draftElevatorOpening

    /// Both attendee + client known → the line names both.
    func test_draftElevatorOpening_includesAttendeeFirstName_andClient() {
        let stripe = makeClient(name: "Stripe", domain: "stripe.com")
        let event = makeEvent(
            attendees: ["Jane Doe"],
            emails: ["jane.doe@stripe.com"]
        )
        let opening = MeetingBriefBuilder.draftElevatorOpening(for: stripe, event: event)
        XCTAssertTrue(opening.contains("Jane"),
                      "Opening must name-check the first attendee")
        XCTAssertTrue(opening.contains("Stripe"),
                      "Opening must mention the matched client")
        XCTAssertTrue(opening.contains("Bonjour"),
                      "Opening line is in French — must start with the FR greeting")
    }

    /// No attendees at all → falls back to a "Bonjour, …" opening
    /// that still reads as Mehdi's voice (no leakage of nil
    /// placeholders into the string).
    func test_draftElevatorOpening_noAttendees_returnsFallbackFrench() {
        let event = makeEvent(attendees: [], emails: [])
        let opening = MeetingBriefBuilder.draftElevatorOpening(for: nil, event: event)
        XCTAssertTrue(opening.hasPrefix("Bonjour"),
                      "Fallback opening still starts with FR greeting")
        XCTAssertFalse(opening.contains("nil"),
                       "Fallback must not leak nil placeholders into the body")
    }

    // MARK: - Determinism + FR-only language contract

    /// Calling the builder twice with identical inputs returns
    /// identical questions/opening — required for tests + screenshot
    /// stability + telemetry de-dupe. `assemble` is MainActor-bound
    /// because `Node` is a SwiftData `@Model`, so the test hops onto
    /// the MainActor for the call.
    @MainActor
    func test_assemble_isDeterministic() {
        let stripe = makeClient(name: "Stripe", domain: "stripe.com")
        let event = makeEvent(emails: ["jane@stripe.com"])
        let now = Date(timeIntervalSince1970: 1_780_086_400)
        let first  = MeetingBriefBuilder.assemble(for: event, clients: [stripe], asOf: now)
        let second = MeetingBriefBuilder.assemble(for: event, clients: [stripe], asOf: now)
        XCTAssertEqual(first.discoveryQuestions, second.discoveryQuestions)
        XCTAssertEqual(first.elevatorOpening, second.elevatorOpening)
        XCTAssertEqual(first.detectedClient?.nodeID, second.detectedClient?.nodeID)
        XCTAssertEqual(first.generatedAt, second.generatedAt)
    }

    /// Every generic French question is verifiably in French — we
    /// look for the absence of common English filler words ("the",
    /// "your") and the presence of an FR signal ("vous"). Catches an
    /// accidental EN paste in the generic fallback.
    func test_draftDiscoveryQuestions_areFrench_noEnglishLeak() {
        let event = makeEvent(emails: ["x@y.com"])
        let questions = MeetingBriefBuilder.draftDiscoveryQuestions(for: nil, event: event)
        let lowered = questions.map { $0.lowercased() }
        let englishLeak = lowered.contains { $0.contains(" the ") || $0.contains(" your ") }
        XCTAssertFalse(englishLeak,
                       "Questions must be French — no 'the'/'your' filler leakage")
        let frenchSignal = lowered.contains { $0.contains("vous") || $0.contains("votre") }
        XCTAssertTrue(frenchSignal,
                      "At least one question must address the prospect with 'vous'/'votre'")
    }

    // MARK: - MeetingBriefScheduler helpers

    /// Identifier prefix lives in one place so the scheduler can
    /// prune stale requests. Lock the contract.
    func test_scheduler_identifierIsPrefixed() {
        let id = MeetingBriefScheduler.identifier(for: "abc-123")
        XCTAssertTrue(id.hasPrefix(MeetingBriefScheduler.identifierPrefix))
        XCTAssertEqual(id, "mind.meetingBrief.abc-123")
    }

    /// `mind://brief/<eventID>` deep link composes cleanly even
    /// when the id contains URL-safe characters.
    func test_scheduler_deepLinkURLIncludesEventID() {
        let url = MeetingBriefScheduler.deepLinkURL(for: "abc-123")
        XCTAssertEqual(url?.absoluteString, "mind://brief/abc-123")
    }

    /// plannedFireDate: morning slot in the future → fire at 7am.
    func test_scheduler_plannedFire_morningSlotFuture_returnsMorning() {
        let calendar = Calendar(identifier: .gregorian)
        // start = tomorrow 14h00 local; now = tonight 22h00 local.
        let now = makeDate(year: 2026, month: 5, day: 19, hour: 22, calendar: calendar)
        let start = makeDate(year: 2026, month: 5, day: 20, hour: 14, calendar: calendar)
        let fire = MeetingBriefScheduler.plannedFireDate(
            for: start,
            morningHour: 7,
            now: now,
            calendar: calendar
        )
        XCTAssertNotNil(fire)
        let comps = calendar.dateComponents([.hour, .minute, .day], from: fire!)
        XCTAssertEqual(comps.hour, 7, "Should fire at morningHour 7 the day of the meeting")
        XCTAssertEqual(comps.minute, 0)
        XCTAssertEqual(comps.day, 20)
    }

    /// plannedFireDate: morning slot already passed → fall back to
    /// `start - 1h` so the user still gets a heads-up.
    func test_scheduler_plannedFire_morningSlotPassed_returnsOneHourBefore() {
        let calendar = Calendar(identifier: .gregorian)
        let now = makeDate(year: 2026, month: 5, day: 20, hour: 11, calendar: calendar)
        let start = makeDate(year: 2026, month: 5, day: 20, hour: 14, calendar: calendar)
        let fire = MeetingBriefScheduler.plannedFireDate(
            for: start,
            morningHour: 7,
            now: now,
            calendar: calendar
        )
        XCTAssertNotNil(fire)
        // 14h00 - 1h = 13h00.
        XCTAssertEqual(
            calendar.dateComponents([.hour], from: fire!).hour,
            13,
            "Past-morning meeting falls back to start - 1h"
        )
    }

    // MARK: - Notification body templating

    /// Body folds in the meeting time + the event title via the
    /// localized format string.
    func test_scheduler_notificationBody_containsTimeAndTitle() {
        let event = makeEvent(title: "Stripe discovery")
        let body = MeetingBriefScheduler.notificationBody(for: event)
        let timeString = event.startDate.formatted(date: .omitted, time: .shortened)
        XCTAssertTrue(body.contains(timeString),
                      "Body must surface the meeting time")
        XCTAssertTrue(body.contains("Stripe discovery"),
                      "Body must surface the event title")
    }

    // MARK: - Helpers

    private func makeDate(
        year: Int, month: Int, day: Int, hour: Int,
        calendar: Calendar
    ) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = 0
        return calendar.date(from: comps)!
    }
}
