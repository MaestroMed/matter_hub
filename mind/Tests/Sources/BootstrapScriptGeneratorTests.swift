import XCTest
@testable import BootstrapKit
@testable import GraphCore

/// v1.0-alpha.6 — Locks the pure shell-script generator.
/// Every assertion walks the generated `String` so no shell, no
/// FileManager, no clock reads.
final class BootstrapScriptGeneratorTests: XCTestCase {

    // MARK: - Fixture

    private func sampleBlueprint(
        admin: Bool = false,
        blog: Bool = false,
        i18n: Bool = false,
        stripe: Bool = false,
        stack: ProjectStack = .nextjs
    ) -> BootstrapBlueprint {
        BootstrapBlueprint(
            id: UUID(uuidString: "DEADBEEF-1111-2222-3333-444444444444")!,
            projectName: "AZ Construction",
            slug: "az-construction",
            host: "www.azconstruction.fr",
            githubOrg: "MaestroMed",
            stack: stack,
            primaryColor: "#1F6FEB",
            contractType: .retainer,
            monthlyRecurringRevenueEUR: 290,
            includeAdminBackoffice: admin,
            includeBlogMDX: blog,
            includeI18nFREN: i18n,
            includeStripe: stripe,
            generatedAt: Date(timeIntervalSince1970: 1_747_699_200)
        )
    }

    // MARK: - Prelude

    func test_script_startsWith_bashShebang() {
        let script = BootstrapScriptGenerator.bashScript(for: sampleBlueprint())
        XCTAssertTrue(script.hasPrefix("#!/usr/bin/env bash\n"),
                      "Script must start with the bash shebang so chmod+x works on macOS without ambiguity")
    }

    func test_script_includesStrictMode_setE_setU_setO() {
        let script = BootstrapScriptGenerator.bashScript(for: sampleBlueprint())
        XCTAssertTrue(script.contains("set -e\n"),
                      "Script must exit on first failed command via `set -e`")
        XCTAssertTrue(script.contains("set -u\n"),
                      "Script must fail on unset vars via `set -u`")
        XCTAssertTrue(script.contains("set -o pipefail\n"),
                      "Script must propagate pipe failures via `set -o pipefail`")
    }

    // MARK: - Workspace

    func test_script_makesWorkspaceUnderDeveloperFolder() {
        let script = BootstrapScriptGenerator.bashScript(for: sampleBlueprint())
        XCTAssertTrue(script.contains("mkdir -p \"$HOME/Developer/az-construction\""),
                      "Workspace must land under ~/Developer/<slug> — Mehdi's convention")
    }

    // MARK: - GitHub

    func test_script_includesGhRepoCreate_withCorrectOrgAndSlug() {
        let script = BootstrapScriptGenerator.bashScript(for: sampleBlueprint())
        XCTAssertTrue(script.contains("gh repo create MaestroMed/az-construction --private"),
                      "gh repo create must target the exact org/slug — got\n\(script)")
    }

    func test_script_includesGitPushOriginMain() {
        let script = BootstrapScriptGenerator.bashScript(for: sampleBlueprint())
        XCTAssertTrue(script.contains("git push -u origin main"),
                      "Script must push the initial commit to origin/main")
    }

    // MARK: - Vercel

    func test_script_includesVercelLinkLine_softFail() {
        let script = BootstrapScriptGenerator.bashScript(for: sampleBlueprint())
        XCTAssertTrue(script.contains("vercel link --project=az-construction --yes"),
                      "Script must link the Vercel project automatically with the slug")
    }

    // MARK: - File heredocs

    func test_script_includesHeredoc_forPackageJSON() {
        let script = BootstrapScriptGenerator.bashScript(for: sampleBlueprint())
        XCTAssertTrue(script.contains("cat > package.json <<'"),
                      "Script must heredoc-write package.json")
    }

    func test_script_includesHeredoc_forLayoutTSX_withMetadataBaseHost() {
        let script = BootstrapScriptGenerator.bashScript(for: sampleBlueprint())
        XCTAssertTrue(script.contains("cat > src/app/layout.tsx <<'"),
                      "Script must heredoc-write layout.tsx")
        XCTAssertTrue(script.contains("https://www.azconstruction.fr"),
                      "layout.tsx must carry metadataBase with the blueprint host")
    }

    func test_script_includesHeredoc_forContactRoute() {
        let script = BootstrapScriptGenerator.bashScript(for: sampleBlueprint())
        XCTAssertTrue(script.contains("cat > src/app/api/contact/route.ts <<'"),
                      "Script must heredoc-write the contact route handler")
    }

    // MARK: - @mind/lead-webhook wiring

    func test_script_alwaysWires_mindLeadWebhook_intoPackageJSONAndContactRoute() {
        let script = BootstrapScriptGenerator.bashScript(for: sampleBlueprint())
        XCTAssertTrue(script.contains("@mind/lead-webhook"),
                      "Every scaffold must reference @mind/lead-webhook so leads forward to MIND cockpit")
        XCTAssertTrue(script.contains("sendLeadToMIND"),
                      "Contact route heredoc must wire sendLeadToMIND() — never lose a lead")
    }

    // MARK: - Optional bundles gating

    func test_script_includesAdminScaffold_ONLY_whenIncludeAdminBackofficeIsTrue() {
        let off = BootstrapScriptGenerator.bashScript(for: sampleBlueprint(admin: false))
        let on  = BootstrapScriptGenerator.bashScript(for: sampleBlueprint(admin: true))
        XCTAssertFalse(off.contains("src/app/admin/page.tsx"),
                       "Admin scaffold must NOT appear when the toggle is off")
        XCTAssertTrue(on.contains("src/app/admin/page.tsx"),
                      "Admin scaffold MUST appear when the toggle is on")
        XCTAssertTrue(on.contains("src/lib/admin/auth.ts"),
                      "Admin scaffold must drop auth.ts too")
    }

    func test_script_includesBlogScaffold_ONLY_whenIncludeBlogMDXIsTrue() {
        let off = BootstrapScriptGenerator.bashScript(for: sampleBlueprint(blog: false))
        let on  = BootstrapScriptGenerator.bashScript(for: sampleBlueprint(blog: true))
        XCTAssertFalse(off.contains("content/blog/hello-world.mdx"))
        XCTAssertTrue(on.contains("content/blog/hello-world.mdx"))
    }

    func test_script_includesStripeScaffold_ONLY_whenIncludeStripeIsTrue() {
        let off = BootstrapScriptGenerator.bashScript(for: sampleBlueprint(stripe: false))
        let on  = BootstrapScriptGenerator.bashScript(for: sampleBlueprint(stripe: true))
        XCTAssertFalse(off.contains("stripe.config.ts"))
        XCTAssertTrue(on.contains("stripe.config.ts"))
        XCTAssertTrue(on.contains("src/app/api/stripe/webhook/route.ts"))
    }

    func test_script_includesI18nScaffold_ONLY_whenIncludeI18nFRENIsTrue() {
        let off = BootstrapScriptGenerator.bashScript(for: sampleBlueprint(i18n: false))
        let on  = BootstrapScriptGenerator.bashScript(for: sampleBlueprint(i18n: true))
        XCTAssertFalse(off.contains("messages/fr.json"))
        XCTAssertTrue(on.contains("messages/fr.json"))
        XCTAssertTrue(on.contains("messages/en.json"))
    }
}
