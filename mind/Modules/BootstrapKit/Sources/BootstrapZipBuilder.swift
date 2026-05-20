import Foundation

/// v1.0-alpha.6 — Bootstrap Scaffolder.
///
/// In-memory archive builder mirroring the file set
/// `BootstrapScriptGenerator` writes via heredocs, exposed as a
/// `[String: Data]` map. The iOS result sheet's "Partager le ZIP"
/// option hands this map to `BootstrapZipPacker` (a small helper
/// in the App layer that wraps Foundation's NSFileCoordinator +
/// `Compression`) to materialise a `<slug>-scaffold.zip` file on
/// the user's iCloud Drive for AirDrop.
///
/// The builder is **pure** — same blueprint → same archive bytes
/// for every file. The zip-on-disk step is intentionally NOT in
/// this module so testing stays trivial: every assertion walks
/// the `files` dictionary directly without touching disk or
/// reaching for the Compression framework.
public struct BootstrapArchive: Sendable, Hashable {

    /// Forward-slashed relative path → file bytes. Always non-empty
    /// (`README.md` is mandatory) and always sortable for stable
    /// test snapshots.
    public let files: [String: Data]

    /// Human-friendly slug for the parent folder name —
    /// `"az-construction-scaffold"`, used by the App layer to
    /// compose the AirDrop filename.
    public let folderSlug: String

    /// Total size of `files` in bytes. Cached at construction so
    /// the size-budget test doesn't redundantly sum the dict.
    public let totalBytes: Int

    public init(files: [String: Data], folderSlug: String) {
        precondition(files["README.md"] != nil,
                     "BootstrapArchive must contain README.md")
        self.files = files
        self.folderSlug = folderSlug
        self.totalBytes = files.values.reduce(0) { $0 + $1.count }
    }

    /// Sorted file paths for stable iteration in tests.
    public var sortedFilePaths: [String] {
        files.keys.sorted()
    }
}

/// Pure builder that turns a blueprint into the in-memory file map.
/// Mirrors the same files `BootstrapScriptGenerator` would heredoc
/// — divergence between the two means a regression in either path,
/// so the test suite asserts both produce the same file set.
public enum BootstrapZipBuilder {

    /// Builds the in-memory archive. Deterministic for a given
    /// blueprint (modulo the timestamp the blueprint already carries
    /// in its `generatedAt`).
    public static func archive(for blueprint: BootstrapBlueprint) -> BootstrapArchive {
        var files: [String: Data] = [:]

        func write(_ path: String, _ contents: String) {
            files[path] = Data(contents.utf8)
        }

        // Universal files (all stacks).
        write("README.md", TemplateLibrary.readme(
            projectName: blueprint.projectName,
            host: blueprint.host
        ))
        write(".gitignore", TemplateLibrary.gitignore())
        write(".cursorrules", TemplateLibrary.cursorrules(projectName: blueprint.projectName))
        write(".env.example", TemplateLibrary.envExample(includeStripe: blueprint.includeStripe))
        write("package.json", TemplateLibrary.packageJSON(
            slug: blueprint.slug,
            stack: blueprint.stack,
            includeAdmin: blueprint.includeAdminBackoffice,
            includeBlog: blueprint.includeBlogMDX,
            includeStripe: blueprint.includeStripe
        ))

        // Next.js-only files.
        if blueprint.stack == .nextjs {
            write("next.config.ts", TemplateLibrary.nextConfigTS())
            write("tsconfig.json", TemplateLibrary.tsconfigJSON())
            write("tailwind.config.ts", TemplateLibrary.tailwindConfigTS(primaryColor: blueprint.primaryColor))
            write("src/app/layout.tsx", TemplateLibrary.layoutTSX(
                host: blueprint.host,
                projectName: blueprint.projectName,
                primaryColor: blueprint.primaryColor
            ))
            write("src/app/page.tsx", TemplateLibrary.pageTSX(projectName: blueprint.projectName))
            write("src/app/globals.css", TemplateLibrary.globalsCSS())
            write("src/app/api/contact/route.ts", TemplateLibrary.contactRouteTS())
            write("src/app/robots.ts", TemplateLibrary.robotsTS(host: blueprint.host))
            write("src/app/sitemap.ts", TemplateLibrary.sitemapTS(host: blueprint.host))
            write("src/lib/email.ts", TemplateLibrary.emailLibTS())
            write("src/lib/rate-limit.ts", TemplateLibrary.rateLimitLibTS())
            write("vercel.json", TemplateLibrary.vercelJSON())
        }

        // Optional bundles.
        if blueprint.includeAdminBackoffice {
            write("src/app/admin/page.tsx", TemplateLibrary.adminPageTSX())
            write("src/lib/admin/auth.ts", TemplateLibrary.adminAuthTS())
        }
        if blueprint.includeBlogMDX {
            write("content/blog/hello-world.mdx", TemplateLibrary.blogSamplePostMDX())
        }
        if blueprint.includeI18nFREN {
            write("i18n.config.ts", TemplateLibrary.nextIntlConfigTS())
            write("messages/fr.json", TemplateLibrary.i18nMessagesFR())
            write("messages/en.json", TemplateLibrary.i18nMessagesEN())
        }
        if blueprint.includeStripe {
            write("stripe.config.ts", TemplateLibrary.stripeConfigTS())
            write("src/app/api/stripe/webhook/route.ts", TemplateLibrary.stripeWebhookRouteTS())
        }

        let folderSlug = "\(blueprint.slug)-scaffold"
        // Telemetry intentionally fires from the UI call-site, which
        // is already on MainActor — keeping this function fully
        // synchronous + non-actor-isolated keeps the test suite from
        // needing async machinery for what is otherwise a pure
        // string-building exercise.
        return BootstrapArchive(files: files, folderSlug: folderSlug)
    }
}
