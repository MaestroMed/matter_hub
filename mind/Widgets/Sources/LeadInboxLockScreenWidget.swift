import WidgetKit
import SwiftUI
import GraphCore

// MARK: - Entry

/// v1.0-alpha.16 — Wraps the cross-process `SharedSnapshot` payload
/// (which the host App refreshes on every `.active` scene phase via
/// `SharedSnapshotWriter.refresh(...)`) with the WidgetKit timeline
/// contract field (`date: Date`). The two columns the widget surface
/// reads are the lead count + the most-recent contact name.
struct LeadInboxLockScreenEntry: TimelineEntry {
    let date: Date
    let leadCount: Int
    let leadLastContact: String?

    static let placeholder = LeadInboxLockScreenEntry(
        date: .now,
        leadCount: SharedSnapshot.placeholder.leadCount,
        leadLastContact: SharedSnapshot.placeholder.leadLastContact
    )

    static let empty = LeadInboxLockScreenEntry(
        date: .now,
        leadCount: 0,
        leadLastContact: nil
    )

    init(date: Date, leadCount: Int, leadLastContact: String?) {
        self.date = date
        self.leadCount = leadCount
        self.leadLastContact = leadLastContact
    }
}

// MARK: - Provider

/// v1.0-alpha.16 — Refreshes every 15 min so the Lock Screen
/// surfaces a sufficiently fresh lead count between the host App's
/// foreground refreshes. iOS still gates the actual wake cadence so
/// this is the maximum reload frequency we ask for.
struct LeadInboxLockScreenProvider: TimelineProvider {
    typealias Entry = LeadInboxLockScreenEntry

    func placeholder(in context: Context) -> LeadInboxLockScreenEntry {
        .placeholder
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (LeadInboxLockScreenEntry) -> Void
    ) {
        if context.isPreview {
            completion(.placeholder)
            return
        }
        completion(fetchEntry())
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<LeadInboxLockScreenEntry>) -> Void
    ) {
        let entry = fetchEntry()
        let leadCount = entry.leadCount
        Task { @MainActor in
            MINDTelemetry.info(
                "widget.timeline.requested",
                data: [
                    "kind": "lead.inbox",
                    "leads": String(leadCount),
                ]
            )
        }
        let next = Calendar.current.date(
            byAdding: .minute,
            value: 15,
            to: .now
        ) ?? .now
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func fetchEntry() -> LeadInboxLockScreenEntry {
        let snapshot = SharedSnapshotWriter.readSnapshot()
        return LeadInboxLockScreenEntry(
            date: .now,
            leadCount: snapshot.leadCount,
            leadLastContact: snapshot.leadLastContact
        )
    }
}

// MARK: - Widget

/// v1.0-alpha.16 — Single `.accessoryRectangular` family surfacing
/// the lead inbox on iOS 26 Lock Screen + StandBy stack + Always-On.
/// Tapping deep-links to `mind://leads` (RootView's `.onOpenURL` flips
/// the leads tab on Home — the route already exists from the
/// Catalyst toolbar wiring).
struct LeadInboxLockScreenWidget: Widget {
    static let kind = "app.mind.ios.widget.lockscreen.leadinbox"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: Self.kind,
            provider: LeadInboxLockScreenProvider()
        ) { entry in
            LeadInboxLockScreenView(entry: entry)
                .widgetURL(URL(string: "mind://leads")!)
                .containerBackground(for: .widget) {
                    Color.clear
                }
        }
        // FR-first display name + description — surfaces in the
        // Lock Screen widget gallery as "Leads" / "Tes derniers
        // leads en un coup d'œil".
        .configurationDisplayName(LocalizedStringResource("widget.leadInbox.title"))
        .description(LocalizedStringResource("widget.leadInbox.description"))
        .supportedFamilies([.accessoryRectangular])
    }
}

// MARK: - View

/// v1.0-alpha.16 — Two-line accessory body. Header surfaces the lead
/// count with a brand-tinted envelope glyph; the body row shows the
/// truncated last contact name. Empty graph collapses to the
/// "Aucun lead" CTA.
struct LeadInboxLockScreenView: View {
    let entry: LeadInboxLockScreenEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "envelope.badge")
                    .font(.system(size: 13, weight: .semibold))
                    .widgetAccentable()
                Text(headerText)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .contentTransition(.numericText())
            }
            if let contact = entry.leadLastContact, !contact.isEmpty {
                Text(contact)
                    .font(.system(.footnote, design: .rounded))
                    .lineLimit(1)
            } else {
                Text("Aucun lead")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// FR header reads "1 lead" / "N leads" / "Aucun lead". The
    /// circle-glyph above already prefixes the row visually so the
    /// brand label is implicit.
    private var headerText: String {
        switch entry.leadCount {
        case 0: return "Aucun lead"
        case 1: return "1 lead"
        default: return "\(entry.leadCount) leads"
        }
    }
}
