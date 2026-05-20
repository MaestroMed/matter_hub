import SwiftUI

/// v1.0-alpha.17 — Lead inbox tab on the Apple Watch. Reads the
/// `mind.watch.leads` snapshot the iPhone host pushed last (offline-
/// first via App Group), surfaces the 5 most-recent leads as a List
/// the user can flick through with the Digital Crown.
///
/// Tap → opens a placeholder dictation sheet (WatchKit Dictation UI).
/// The reply itself is queued back to the iPhone via
/// `WatchConnectivityBridge` in a future iteration; v1.0-alpha.17
/// only proves the read path + tap target.
struct WatchLeadInbox: View {

    @State private var leads: [WatchLeadDigest] = WatchSharedSnapshot.readLeads()
    @State private var dictationLead: WatchLeadDigest?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                header
                if leads.isEmpty {
                    emptyState
                } else {
                    ForEach(leads.prefix(5), id: \.id) { lead in
                        Button {
                            dictationLead = lead
                        } label: {
                            row(lead)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("MIND")
        .onAppear {
            refresh()
        }
        .sheet(item: $dictationLead) { lead in
            WatchDictationPlaceholder(lead: lead)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "tray.full.fill")
                .font(.headline)
            Text("watch.tab.leads.title".watchLocalized)
                .font(.headline)
            Spacer()
            Text(WatchKPIFormatter.leadCount(leads.count))
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(.white.opacity(0.15)))
        }
        .padding(.vertical, 4)
    }

    private func row(_ lead: WatchLeadDigest) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(lead.contactName)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text(WatchKPIFormatter.preview(lead.messagePreview))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.08))
        )
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("watch.empty.leads".watchLocalized)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func refresh() {
        leads = WatchSharedSnapshot.readLeads()
    }
}

/// v1.0-alpha.17 — Placeholder dictation sheet. The full SFSpeech
/// dictation UI plus queued reply via `WatchConnectivityBridge` is a
/// follow-up; this sheet just surfaces the lead context + a CTA
/// stub so the tap target is wired.
private struct WatchDictationPlaceholder: View {
    let lead: WatchLeadDigest

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(lead.contactName)
                    .font(.headline)
                Text(WatchKPIFormatter.preview(lead.messagePreview))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Divider()
                    .padding(.vertical, 4)
                Text("watch.lead.dictate".watchLocalized)
                    .font(.caption.weight(.semibold))
            }
            .padding(8)
        }
    }
}

