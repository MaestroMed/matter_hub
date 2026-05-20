import Foundation
import SwiftData

/// v1.0-alpha.3 — Idempotent demo Leads seeder so HomeView's
/// "Aujourd'hui" inbox isn't empty on the very first cold launch.
///
/// Pattern mirrors `Project.seedDemoProjects(in:)`:
/// - Bails when any Lead already exists (idempotency on every call).
/// - Caller gates on `@AppStorage("mind.demoLeads.seeded")` so a wipe
///   never silently re-injects fake rows.
/// - Returns the inserted count so the call site can fire a
///   telemetry breadcrumb with the actual number.
///
/// The 4 demo leads target AZ Construction (3) + IEF & Co (1) so
/// Mehdi feels the multi-project UX immediately. Receipt times are
/// staggered across "today" so the inbox shows a realistic feed
/// (top row 12 min ago, bottom row 4h ago).
extension Lead {
    /// Insert demo leads for the two flagship projects, idempotent.
    /// Lookup of the parent Project is by exact `name` match — the
    /// seed must run AFTER `Project.seedDemoProjects(in:)` has
    /// landed the 5 real Numelite rows.
    ///
    /// Returns the number of leads actually inserted (0 when any
    /// Lead already exists, or when both target Projects are
    /// missing).
    @discardableResult
    public static func seedDemoLeads(in context: ModelContext) -> Int {
        let existing = (try? context.fetch(FetchDescriptor<Lead>())) ?? []
        guard existing.isEmpty else { return 0 }
        let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        let azc = projects.first { $0.name == "AZ Construction" }
        let ief = projects.first { $0.name == "IEF & Co" }
        guard azc != nil || ief != nil else { return 0 }
        let now = Date.now
        let seeds: [Lead] = [
            Lead(
                receivedAt: now.addingTimeInterval(-12 * 60),
                sourceURL: "https://www.azconstruction.fr/devis",
                formType: .devis,
                contactName: "Sarah Bensalem",
                contactEmail: "sarah.b@gmail.com",
                contactPhone: "06 12 34 56 78",
                message: "Bonjour, je souhaite refaire ma terrasse de 35m² en béton désactivé. Pouvez-vous me communiquer un devis ? Habitation à Vitry-sur-Seine. Merci.",
                rawPayload: #"{"name":"Sarah Bensalem","email":"sarah.b@gmail.com"}"#,
                userAgent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X)",
                project: azc
            ),
            Lead(
                receivedAt: now.addingTimeInterval(-55 * 60),
                sourceURL: "https://www.azconstruction.fr/contact",
                formType: .contact,
                contactName: "Marc Petitjean",
                contactEmail: "marc.petitjean@entreprise-pj.fr",
                contactPhone: "01 45 78 23 11",
                message: "Suite à notre échange téléphonique, je vous confirme le projet de rénovation complète des bureaux Paris 11e. 240m². Pourrions-nous fixer un RDV cette semaine ?",
                rawPayload: #"{"name":"Marc Petitjean"}"#,
                userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_2)",
                project: azc
            ),
            Lead(
                receivedAt: now.addingTimeInterval(-2 * 3600),
                sourceURL: "https://www.iefandco.com/contact",
                formType: .contact,
                contactName: "Lucie Aubry",
                contactEmail: "l.aubry@maisonaubry.fr",
                contactPhone: nil,
                message: "Je suis en train de monter une nouvelle ligne lifestyle et je cherche un partenaire pour la création de notre identité visuelle + e-shop. Budget : 8-12k€. Vos délais ?",
                rawPayload: #"{"name":"Lucie Aubry"}"#,
                userAgent: "Mozilla/5.0 (X11; Linux x86_64)",
                project: ief
            ),
            Lead(
                receivedAt: now.addingTimeInterval(-4 * 3600),
                sourceURL: "https://www.azconstruction.fr/contact",
                formType: .contact,
                contactName: "Pierre Loison",
                contactEmail: "p.loison@hotmail.fr",
                contactPhone: "07 88 12 45 90",
                message: "Demande de devis pour un mur de soutènement, environ 12 mètres linéaires, hauteur 1m80. Habitation à Saint-Maur-des-Fossés.",
                rawPayload: #"{"name":"Pierre Loison"}"#,
                userAgent: "Mozilla/5.0 (iPhone)",
                project: azc
            ),
        ]
        for lead in seeds {
            context.insert(lead)
            // Touch the parent Project so the activity feed reflects
            // the lead landing.
            lead.project?.lastActivityAt = lead.receivedAt
        }
        try? context.save()
        return seeds.count
    }
}
