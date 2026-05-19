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
}
