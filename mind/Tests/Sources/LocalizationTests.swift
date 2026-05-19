import XCTest
import Foundation

/// Locks the i18n contract shipped in v0.7. The .xcstrings catalog
/// is the source of truth for every visible string — these tests make
/// sure both FR and EN sides resolve to known values at runtime via
/// the actual iOS bundle lookup path (not just JSON parsing) so we
/// catch the case where Xcode's catalog compiler drops a translation.
///
/// Strategy: locate the main app bundle from inside the test bundle
/// (host application bundle), then load its localized .lproj
/// directories (en, fr) and resolve known keys against each. If
/// either side returns the raw key, the test fails — that's the
/// fallback iOS uses when a key has no translation, and it's exactly
/// the bug we never want to ship.
final class LocalizationTests: XCTestCase {
    /// The host app bundle (MIND.app). Falls back to the test bundle's
    /// own bundle if the host isn't set, but the unit-test scheme always
    /// has the app as test host so this should never trigger in CI.
    private func appBundle() -> Bundle {
        if let host = Bundle.main.object(forInfoDictionaryKey: "NSExtensionPointIdentifier") as? String,
           !host.isEmpty {
            return Bundle.main
        }
        // Bundle.main here is the test runner; for hosted tests the
        // host app is loaded into the same process so Bundle.main IS
        // the app bundle. That's the path we exercise in CI.
        return Bundle.main
    }

    /// Returns the per-language bundle for `lang` (en or fr), or nil
    /// if the .lproj directory isn't present. iOS lazily packs each
    /// .xcstrings region into a .lproj of its own at compile-time.
    private func localizedBundle(for lang: String) -> Bundle? {
        let app = appBundle()
        guard let path = app.path(forResource: lang, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else { return nil }
        return bundle
    }

    /// Resolve a key in a specific language by loading the appropriate
    /// .lproj bundle. Returns the localized string, or nil if the key
    /// is missing / the bundle isn't there.
    private func localized(_ key: String, lang: String) -> String? {
        guard let bundle = localizedBundle(for: lang) else { return nil }
        let value = bundle.localizedString(forKey: key, value: nil, table: nil)
        // Bundle returns the key itself when the entry is missing. That
        // counts as "not localized" for our purposes.
        return value == key ? nil : value
    }

    // MARK: - Bundle / .lproj contract

    /// The app bundle must contain en.lproj AND fr.lproj. If a
    /// build-config change drops one, every Text() in that region
    /// falls back to the source-language value silently. This test
    /// makes the regression loud.
    func test_appBundle_hasEnAndFrLproj() {
        let app = appBundle()
        XCTAssertNotNil(app.path(forResource: "en", ofType: "lproj"),
                        "App bundle must contain en.lproj")
        XCTAssertNotNil(app.path(forResource: "fr", ofType: "lproj"),
                        "App bundle must contain fr.lproj")
    }

    // MARK: - Anchor keys

    /// Welcome-flow empty-state title — the first FR string the user
    /// sees on a fresh install. Locks both translations.
    func test_homeEmptyTitle_resolvesBothLanguages() {
        XCTAssertEqual(localized("home.empty.title", lang: "en"), "Welcome to MIND")
        XCTAssertEqual(localized("home.empty.title", lang: "fr"), "Bienvenue dans MIND")
    }

    /// Onboarding final CTA — the user's first commit-action. Locking
    /// both translations makes sure the button never reads "Start" in
    /// the FR build by accident.
    func test_onboardingStart_resolvesBothLanguages() {
        XCTAssertEqual(localized("onboarding.start", lang: "en"), "Start")
        XCTAssertEqual(localized("onboarding.start", lang: "fr"), "Commencer")
    }

    /// Audit-running labels are on screen for ~2 minutes per audit —
    /// the most-visible "running" copy in the app. Lock the contract.
    func test_auditPhases_resolveBothLanguages() {
        XCTAssertEqual(localized("audit.phase.probing",      lang: "en"), "Probes")
        XCTAssertEqual(localized("audit.phase.probing",      lang: "fr"), "Sondes")
        XCTAssertEqual(localized("audit.phase.synthesizing", lang: "en"), "Synthesis")
        XCTAssertEqual(localized("audit.phase.synthesizing", lang: "fr"), "Synthèse")
        XCTAssertEqual(localized("audit.phase.ready",        lang: "en"), "Ready")
        XCTAssertEqual(localized("audit.phase.ready",        lang: "fr"), "Prêt")
    }

    /// Settings header — the user's gateway to every preference.
    /// If "Settings" / "Réglages" drifts, the danger-zone alerts (which
    /// reference Settings) also drift. Lock it.
    func test_settingsHeader_resolvesBothLanguages() {
        XCTAssertEqual(localized("settings.header.title", lang: "en"), "Settings")
        XCTAssertEqual(localized("settings.header.title", lang: "fr"), "Réglages")
    }

    /// Capture sheet title — every Quick Capture starts here.
    func test_captureTitle_resolvesBothLanguages() {
        XCTAssertEqual(localized("capture.title", lang: "en"), "Capture")
        XCTAssertEqual(localized("capture.title", lang: "fr"), "Capture")
    }

    /// Greeting line (greeting.morning) — on every Home open between
    /// 5am and noon. Anchor the FR side so a future merge doesn't
    /// regress it to a leftover French phrase.
    func test_greetingMorning_resolvesBothLanguages() {
        XCTAssertEqual(localized("greeting.morning", lang: "en"), "Good morning")
        XCTAssertEqual(localized("greeting.morning", lang: "fr"), "Bonjour")
    }

    /// v0.13 — Contacts integration surfaces a toast on the next
    /// foreground after a vCard share lands in the graph. Make sure
    /// both translations exist so the FR build doesn't fall back to
    /// the EN string.
    func test_shareContactStrings_resolveBothLanguages() {
        XCTAssertEqual(localized("share.contact.added.toast", lang: "en"), "Contact added to MIND")
        XCTAssertEqual(localized("share.contact.added.toast", lang: "fr"), "Contact ajouté à MIND")
        XCTAssertEqual(localized("share.contact.empty.fallback", lang: "en"), "Untitled contact")
        XCTAssertEqual(localized("share.contact.empty.fallback", lang: "fr"), "Contact sans nom")
    }

    /// v0.14 — Mail capture surfaces a toast on the next foreground
    /// after an email share lands in the graph, and uses a localized
    /// fallback when the email has no Subject header. Both
    /// translations must exist so the FR build doesn't fall back to
    /// the EN string.
    func test_shareMailStrings_resolveBothLanguages() {
        XCTAssertEqual(localized("share.mail.added.toast", lang: "en"), "Email added to MIND")
        XCTAssertEqual(localized("share.mail.added.toast", lang: "fr"), "E-mail ajouté à MIND")
        XCTAssertEqual(localized("share.mail.empty.fallback", lang: "en"), "Untitled email")
        XCTAssertEqual(localized("share.mail.empty.fallback", lang: "fr"), "E-mail sans sujet")
    }

    /// v0.15 — Knowledge graph tab. Lock both translations of the tab
    /// title and the empty-state copy so the FR build never falls back
    /// to the EN string on a fresh install where the graph is empty.
    func test_graphStrings_resolveBothLanguages() {
        XCTAssertEqual(localized("tab.graph",          lang: "en"), "Graph")
        XCTAssertEqual(localized("tab.graph",          lang: "fr"), "Graphe")
        XCTAssertEqual(localized("graph.empty.title",  lang: "en"), "Your graph is empty")
        XCTAssertEqual(localized("graph.empty.title",  lang: "fr"), "Ton graphe est vide")
    }

    /// v0.16 — Weekly digest card on HomeView. Lock the title + the
    /// narrative fallback in both languages so a missing model
    /// response on Sunday night never falls back to the EN copy on
    /// a FR device. The detail-sheet title is locked too — it's the
    /// only string visible after the user taps the card.
    func test_weeklyDigestStrings_resolveBothLanguages() {
        XCTAssertEqual(localized("home.weekly.title",                lang: "en"), "Weekly digest")
        XCTAssertEqual(localized("home.weekly.title",                lang: "fr"), "Bilan de la semaine")
        XCTAssertEqual(localized("home.weekly.narrative.fallback",   lang: "en"), "A solid week.")
        XCTAssertEqual(localized("home.weekly.narrative.fallback",   lang: "fr"), "Une semaine bien remplie.")
        XCTAssertEqual(localized("home.weekly.detail.title",         lang: "en"), "Your week, in detail")
        XCTAssertEqual(localized("home.weekly.detail.title",         lang: "fr"), "Ta semaine, en détail")
    }

    /// v0.19 — Photo OCR strings. The Photo button + the spinner + the
    /// "no text found" empty-state all live in the QuickCaptureSheet,
    /// which is the first surface every user touches once they install
    /// MIND. Lock both translations so the FR build never falls back
    /// to the EN copy on a non-trivial path.
    func test_capturePhotoStrings_resolveBothLanguages() {
        XCTAssertEqual(localized("capture.photo.button",         lang: "en"), "Capture a photo")
        XCTAssertEqual(localized("capture.photo.button",         lang: "fr"), "Capturer une photo")
        XCTAssertEqual(localized("capture.photo.ocrInProgress",  lang: "en"), "Reading the photo…")
        XCTAssertEqual(localized("capture.photo.ocrInProgress",  lang: "fr"), "Lecture de la photo…")
        XCTAssertEqual(localized("capture.photo.ocrComplete",    lang: "en"), "Text extracted from the photo")
        XCTAssertEqual(localized("capture.photo.ocrComplete",    lang: "fr"), "Texte extrait de la photo")
        XCTAssertEqual(localized("capture.photo.empty.fallback", lang: "en"), "No text recognised on this photo.")
        XCTAssertEqual(localized("capture.photo.empty.fallback", lang: "fr"), "Aucun texte reconnu sur cette photo.")
    }

    /// v0.20 — TestFlight beta strings. The BETA badge in Settings →
    /// About, the Beta-section rows that open the TestFlight feedback
    /// + public join URLs, and the dismissible HomeView welcome banner
    /// all ship to external testers via TestFlight. Lock both
    /// translations so the FR build never silently regresses to the
    /// EN copy on the most public surface MIND has.
    func test_betaStrings_resolveBothLanguages() {
        XCTAssertEqual(localized("about.beta.badge",              lang: "en"), "BETA")
        XCTAssertEqual(localized("about.beta.badge",              lang: "fr"), "BÊTA")

        XCTAssertEqual(localized("settings.beta.section",         lang: "en"), "Beta")
        XCTAssertEqual(localized("settings.beta.section",         lang: "fr"), "Beta")
        XCTAssertEqual(localized("settings.beta.feedback.button", lang: "en"), "Send feedback via TestFlight")
        XCTAssertEqual(localized("settings.beta.feedback.button", lang: "fr"), "Envoyer un feedback via TestFlight")
        XCTAssertEqual(localized("settings.beta.join.button",     lang: "en"), "Join the beta")
        XCTAssertEqual(localized("settings.beta.join.button",     lang: "fr"), "Rejoindre la beta")

        XCTAssertEqual(localized("home.beta.banner.title",        lang: "en"), "You're in the MIND beta")
        XCTAssertEqual(localized("home.beta.banner.title",        lang: "fr"), "Tu es dans la beta de MIND")
        XCTAssertEqual(localized("home.beta.banner.cta",          lang: "en"), "Send feedback")
        XCTAssertEqual(localized("home.beta.banner.cta",          lang: "fr"), "Donner ton feedback")
        XCTAssertEqual(localized("home.beta.banner.dismiss",      lang: "en"), "Later")
        XCTAssertEqual(localized("home.beta.banner.dismiss",      lang: "fr"), "Plus tard")
    }

    /// v0.21 — Client Portal generator strings. Locks every FR + EN
    /// key surfaced by the ExportSheet row + the success bottom
    /// sheet so a careless catalogue edit can't ship a portal flow
    /// where half the labels fall back to raw keys.
    func test_clientPortalStrings_resolveBothLanguages() {
        XCTAssertEqual(localized("audit.export.portal.title",                lang: "en"), "Generate client portal")
        XCTAssertEqual(localized("audit.export.portal.title",                lang: "fr"), "Générer le portail client")

        XCTAssertEqual(localized("audit.export.portal.subtitle",             lang: "en"), "Self-contained HTML site, ready to drop on Vercel.")
        XCTAssertEqual(localized("audit.export.portal.subtitle",             lang: "fr"), "Site HTML autonome, prêt à déposer sur Vercel.")

        XCTAssertEqual(localized("audit.export.portal.error.title",          lang: "en"), "Client portal failed")
        XCTAssertEqual(localized("audit.export.portal.error.title",          lang: "fr"), "Échec du portail client")

        XCTAssertEqual(localized("audit.export.portal.success.title",        lang: "en"), "Client portal generated")
        XCTAssertEqual(localized("audit.export.portal.success.title",        lang: "fr"), "Portail client généré")
        XCTAssertEqual(localized("audit.export.portal.success.openInFiles",  lang: "en"), "Open in Files")
        XCTAssertEqual(localized("audit.export.portal.success.openInFiles",  lang: "fr"), "Ouvrir dans Fichiers")
        XCTAssertEqual(localized("audit.export.portal.success.share",        lang: "en"), "Share folder")
        XCTAssertEqual(localized("audit.export.portal.success.share",        lang: "fr"), "Partager le dossier")
    }

    /// v0.22 — Live broadcast strings. Locks every FR + EN key
    /// surfaced by the AuditSheet toggle + the broadcast share sheet
    /// so a careless catalogue edit can't ship a broadcast flow where
    /// half the labels fall back to raw keys.
    func test_liveBroadcastStrings_resolveBothLanguages() {
        XCTAssertEqual(localized("audit.broadcast.toggle.title",    lang: "en"), "Broadcast live")
        XCTAssertEqual(localized("audit.broadcast.toggle.title",    lang: "fr"), "Diffuser en direct")

        XCTAssertEqual(localized("audit.broadcast.toggle.subtitle", lang: "en"),
                       "Your client can follow the audit live in their browser.")
        XCTAssertEqual(localized("audit.broadcast.toggle.subtitle", lang: "fr"),
                       "Le client peut suivre l'audit en temps réel sur son navigateur.")

        XCTAssertEqual(localized("audit.broadcast.sheet.title",     lang: "en"), "Live broadcast ready")
        XCTAssertEqual(localized("audit.broadcast.sheet.title",     lang: "fr"), "Diffusion en direct prête")

        XCTAssertEqual(localized("audit.broadcast.url.copy",        lang: "en"), "Copy link")
        XCTAssertEqual(localized("audit.broadcast.url.copy",        lang: "fr"), "Copier le lien")

        XCTAssertEqual(localized("audit.broadcast.url.copied",      lang: "en"), "Link copied")
        XCTAssertEqual(localized("audit.broadcast.url.copied",      lang: "fr"), "Lien copié")

        XCTAssertEqual(localized("audit.broadcast.qr.title",        lang: "en"), "Scan to open")
        XCTAssertEqual(localized("audit.broadcast.qr.title",        lang: "fr"), "Scanner pour ouvrir")

        XCTAssertEqual(localized("audit.broadcast.error.title",     lang: "en"), "Broadcast failed")
        XCTAssertEqual(localized("audit.broadcast.error.title",     lang: "fr"), "Échec de la diffusion")
    }

    /// v0.23 — Generative redesign mockup strings. Locks every FR +
    /// EN key surfaced by the AuditSheet Vision section + the
    /// portal HTML Vision gallery so a careless catalogue edit
    /// can't ship a redesign-vision flow where the carousel
    /// caption silently falls back to a raw key.
    func test_redesignVisionStrings_resolveBothLanguages() {
        XCTAssertEqual(localized("audit.vision.section.title",    lang: "en"), "Vision: your site, redrawn")
        XCTAssertEqual(localized("audit.vision.section.title",    lang: "fr"), "Vision : votre site, refait")

        XCTAssertEqual(localized("audit.vision.generating",       lang: "en"), "Generating…")
        XCTAssertEqual(localized("audit.vision.generating",       lang: "fr"), "Génération en cours…")

        XCTAssertEqual(localized("audit.vision.empty.keyMissing", lang: "en"),
                       "Connect your OpenAI key in Settings to see redesign visions.")
        XCTAssertEqual(localized("audit.vision.empty.keyMissing", lang: "fr"),
                       "Connecte ta clé OpenAI dans Réglages pour voir les visions de redesign.")

        XCTAssertEqual(localized("audit.vision.tap.detail",       lang: "en"), "BASED ON")
        XCTAssertEqual(localized("audit.vision.tap.detail",       lang: "fr"), "BASÉ SUR")

        XCTAssertEqual(localized("portal.vision.section.title",   lang: "en"), "Your site, redrawn")
        XCTAssertEqual(localized("portal.vision.section.title",   lang: "fr"), "Votre site, refait")

        XCTAssertEqual(localized("portal.vision.caption.prefix",  lang: "en"), "Recommendation")
        XCTAssertEqual(localized("portal.vision.caption.prefix",  lang: "fr"), "Recommandation")
    }

    /// v0.24 — Battle Mode strings. Locks every FR + EN key
    /// surfaced by the BattleSheet form / running / completed
    /// states + the HomeView secondary CTA so a careless
    /// catalogue edit can't ship the cinematic 4-way comparison
    /// with half its labels falling back to raw keys on FR.
    func test_battleModeStrings_resolveBothLanguages() {
        XCTAssertEqual(localized("battle.title",                    lang: "en"), "Battle Mode")
        XCTAssertEqual(localized("battle.title",                    lang: "fr"), "Mode Battle")

        XCTAssertEqual(localized("battle.cta.start",                lang: "en"), "Start the battle")
        XCTAssertEqual(localized("battle.cta.start",                lang: "fr"), "Lancer la battle")

        XCTAssertEqual(localized("battle.podium.title",             lang: "en"), "Who wins what")
        XCTAssertEqual(localized("battle.podium.title",             lang: "fr"), "Qui gagne quoi")

        XCTAssertEqual(localized("battle.winner.badge",             lang: "en"), "Wins")
        XCTAssertEqual(localized("battle.winner.badge",             lang: "fr"), "Gagne")

        XCTAssertEqual(localized("battle.metric.overall",           lang: "en"), "Overall")
        XCTAssertEqual(localized("battle.metric.overall",           lang: "fr"), "Global")
        XCTAssertEqual(localized("battle.metric.security",          lang: "en"), "Security")
        XCTAssertEqual(localized("battle.metric.security",          lang: "fr"), "Sécurité")

        XCTAssertEqual(localized("home.battleCard.title",           lang: "en"), "Battle Mode")
        XCTAssertEqual(localized("home.battleCard.title",           lang: "fr"), "Mode Battle")
    }

    /// v0.25 — ROI Calculator strings. Locks every FR + EN key
    /// surfaced by the AuditSheet hero card + the per-QW inline
    /// ROI badge + the methodology modal so a careless catalogue
    /// edit can't ship a portal where the "+€18 700/mo" hero falls
    /// back to a raw key on FR. The 8 keys map 1:1 to the v0.25
    /// task list in ULTRAPLAN.
    func test_roiCalculatorStrings_resolveBothLanguages() {
        XCTAssertEqual(localized("roi.hero.total.label",      lang: "en"), "ESTIMATED MONTHLY ROI")
        XCTAssertEqual(localized("roi.hero.total.label",      lang: "fr"), "ROI MENSUEL ESTIMÉ")

        XCTAssertEqual(localized("roi.hero.annualized.label", lang: "en"), "Projected over 12 months: %@")
        XCTAssertEqual(localized("roi.hero.annualized.label", lang: "fr"), "Projeté sur 12 mois : %@")

        XCTAssertEqual(localized("roi.confidence.low",        lang: "en"), "low confidence")
        XCTAssertEqual(localized("roi.confidence.low",        lang: "fr"), "confiance faible")
        XCTAssertEqual(localized("roi.confidence.medium",     lang: "en"), "moderate confidence")
        XCTAssertEqual(localized("roi.confidence.medium",     lang: "fr"), "confiance modérée")
        XCTAssertEqual(localized("roi.confidence.high",       lang: "en"), "high confidence")
        XCTAssertEqual(localized("roi.confidence.high",       lang: "fr"), "confiance élevée")

        XCTAssertEqual(localized("roi.per.month.suffix",      lang: "en"), "/mo")
        XCTAssertEqual(localized("roi.per.month.suffix",      lang: "fr"), "/mois")

        XCTAssertEqual(localized("roi.methodology.button",    lang: "en"), "Methodology")
        XCTAssertEqual(localized("roi.methodology.button",    lang: "fr"), "Méthodologie")

        XCTAssertEqual(localized("roi.qw.badge.format",       lang: "en"), "+%1$@ %2$@")
        XCTAssertEqual(localized("roi.qw.badge.format",       lang: "fr"), "+%1$@ %2$@")

        XCTAssertNotNil(localized("roi.methodology.body", lang: "en"))
        XCTAssertNotNil(localized("roi.methodology.body", lang: "fr"))
    }
}
