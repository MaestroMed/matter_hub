import Foundation
import GraphCore

/// v1.0-alpha.6 — Production-grade Next.js 15 + Tailwind 4 template
/// strings. Each `static func` returns the literal file contents the
/// scaffolder writes into the freshly-cloned repo via a heredoc (in
/// `BootstrapScriptGenerator`) or into the in-memory archive (in
/// `BootstrapZipBuilder`).
///
/// Conventions
/// -----------
/// - Every template is pure: no I/O, no clock reads, no env lookups.
///   That keeps `TemplateLibraryTests` trivially testable and the
///   generators deterministic for a given blueprint.
/// - The strings are stored verbatim — no template-string escaping —
///   because the heredocs in `BootstrapScriptGenerator` use the
///   single-quoted `cat <<'EOF'` form which disables shell expansion.
/// - Templates target Mehdi's IEF & Co / AZ Construction baseline:
///   Next.js 15 app router, React 19, Tailwind 4, TypeScript strict,
///   Resend for transactional email, Zod for validation, and a
///   `vercel.json` carrying the security headers Mehdi's lighthouse
///   audits depend on.
public enum TemplateLibrary {

    // MARK: - package.json

    /// `package.json` carrying Next.js 15 + Tailwind 4 + the optional
    /// add-ons each toggle expands. Stack-aware: WordPress / Shopify
    /// scaffolds fall back to a README-only repo (an empty `package.json`
    /// with a placeholder script) because the Next.js dependency
    /// graph would be nonsensical there.
    public static func packageJSON(
        slug: String,
        stack: ProjectStack,
        includeAdmin: Bool,
        includeBlog: Bool,
        includeStripe: Bool
    ) -> String {
        guard stack == .nextjs else {
            // Non-Next.js scaffolds get a minimal placeholder so the
            // repo is still `npm install`-able after the user wires
            // the actual stack.
            return """
            {
              "name": "\(slug)",
              "version": "0.1.0",
              "private": true,
              "description": "Scaffolded by MIND — stack: \(stack.rawValue)",
              "scripts": {
                "dev": "echo \\"Wire your \(stack.rawValue) stack here\\""
              }
            }
            """
        }
        // Build dependency list. We use stable, production-ready
        // versions Mehdi already runs on AZ Construction. Caret
        // ranges keep patch-level upgrades automatic without
        // surprise majors.
        var deps: [String] = [
            "    \"next\": \"15.0.3\"",
            "    \"react\": \"19.0.0\"",
            "    \"react-dom\": \"19.0.0\"",
            "    \"resend\": \"^4.0.1\"",
            "    \"zod\": \"^3.23.8\"",
        ]
        if includeAdmin {
            deps.append("    \"bcryptjs\": \"^2.4.3\"")
            deps.append("    \"jose\": \"^5.9.6\"")
            deps.append("    \"@tiptap/react\": \"^2.10.3\"")
            deps.append("    \"@tiptap/starter-kit\": \"^2.10.3\"")
            deps.append("    \"drizzle-orm\": \"^0.36.4\"")
            deps.append("    \"postgres\": \"^3.4.5\"")
        }
        if includeBlog {
            deps.append("    \"next-mdx-remote\": \"^5.0.0\"")
            deps.append("    \"gray-matter\": \"^4.0.3\"")
        }
        if includeStripe {
            deps.append("    \"stripe\": \"^17.4.0\"")
        }
        // Always include @mind/lead-webhook so the /api/contact
        // route can forward leads to Mehdi's cockpit.
        deps.append("    \"@mind/lead-webhook\": \"^0.1.0\"")

        let devDeps: [String] = [
            "    \"typescript\": \"^5.7.2\"",
            "    \"@types/node\": \"^22.10.1\"",
            "    \"@types/react\": \"^19.0.1\"",
            "    \"@types/react-dom\": \"^19.0.1\"",
            "    \"tailwindcss\": \"^4.0.0-beta.6\"",
            "    \"@tailwindcss/postcss\": \"^4.0.0-beta.6\"",
            "    \"postcss\": \"^8.4.49\"",
            "    \"eslint\": \"^9.16.0\"",
            "    \"eslint-config-next\": \"15.0.3\"",
        ]

        let depsBlock = deps.sorted().joined(separator: ",\n")
        let devDepsBlock = devDeps.sorted().joined(separator: ",\n")

        return """
        {
          "name": "\(slug)",
          "version": "0.1.0",
          "private": true,
          "description": "Scaffolded by MIND — Next.js 15 + Tailwind 4.",
          "scripts": {
            "dev": "next dev",
            "build": "next build",
            "start": "next start",
            "lint": "next lint",
            "typecheck": "tsc --noEmit"
          },
          "dependencies": {
        \(depsBlock)
          },
          "devDependencies": {
        \(devDepsBlock)
          }
        }
        """
    }

    // MARK: - next.config.ts

    /// Modern Next.js 15 config. Strict TS, image domains kept
    /// minimal (Mehdi adds CDN domains per-project), and the
    /// experimental flags Mehdi already runs in production.
    public static func nextConfigTS() -> String {
        """
        import type { NextConfig } from 'next'

        const nextConfig: NextConfig = {
          reactStrictMode: true,
          typedRoutes: true,
          experimental: {
            optimizePackageImports: ['lucide-react'],
          },
          images: {
            remotePatterns: [
              { protocol: 'https', hostname: '**.vercel-storage.com' },
            ],
          },
        }

        export default nextConfig
        """
    }

    // MARK: - tsconfig.json

    public static func tsconfigJSON() -> String {
        """
        {
          "compilerOptions": {
            "target": "ES2022",
            "lib": ["dom", "dom.iterable", "esnext"],
            "allowJs": false,
            "skipLibCheck": true,
            "strict": true,
            "noEmit": true,
            "esModuleInterop": true,
            "module": "esnext",
            "moduleResolution": "bundler",
            "resolveJsonModule": true,
            "isolatedModules": true,
            "jsx": "preserve",
            "incremental": true,
            "plugins": [{ "name": "next" }],
            "paths": {
              "@/*": ["./src/*"]
            }
          },
          "include": ["next-env.d.ts", "**/*.ts", "**/*.tsx", ".next/types/**/*.ts"],
          "exclude": ["node_modules"]
        }
        """
    }

    // MARK: - tailwind.config.ts

    public static func tailwindConfigTS(primaryColor: String) -> String {
        """
        import type { Config } from 'tailwindcss'

        const config: Config = {
          content: [
            './src/pages/**/*.{js,ts,jsx,tsx,mdx}',
            './src/components/**/*.{js,ts,jsx,tsx,mdx}',
            './src/app/**/*.{js,ts,jsx,tsx,mdx}',
          ],
          theme: {
            extend: {
              colors: {
                primary: '\(primaryColor)',
              },
              fontFamily: {
                sans: ['var(--font-inter)', 'system-ui', 'sans-serif'],
              },
            },
          },
          plugins: [],
        }

        export default config
        """
    }

    // MARK: - src/app/layout.tsx

    /// `app/layout.tsx` with the SEO + analytics baseline Mehdi runs
    /// on every shipped site. The `metadataBase` is critical — Next
    /// fails the OG image generation when it's missing.
    public static func layoutTSX(
        host: String,
        projectName: String,
        primaryColor: String
    ) -> String {
        """
        import type { Metadata, Viewport } from 'next'
        import { Inter } from 'next/font/google'
        import { Analytics } from '@vercel/analytics/next'
        import './globals.css'

        const inter = Inter({ subsets: ['latin'], variable: '--font-inter' })

        export const metadata: Metadata = {
          metadataBase: new URL('https://\(host)'),
          title: {
            default: '\(projectName)',
            template: '%s · \(projectName)',
          },
          description: 'Site officiel de \(projectName).',
          openGraph: {
            type: 'website',
            locale: 'fr_FR',
            url: 'https://\(host)',
            siteName: '\(projectName)',
            images: [{ url: '/og.png', width: 1200, height: 630, alt: '\(projectName)' }],
          },
          robots: {
            index: true,
            follow: true,
            googleBot: { index: true, follow: true, 'max-image-preview': 'large' },
          },
          alternates: { canonical: 'https://\(host)' },
        }

        export const viewport: Viewport = {
          themeColor: '\(primaryColor)',
          width: 'device-width',
          initialScale: 1,
        }

        export default function RootLayout({ children }: { children: React.ReactNode }) {
          return (
            <html lang="fr" className={inter.variable}>
              <body className="bg-white text-neutral-900 antialiased">
                {children}
                <Analytics />
              </body>
            </html>
          )
        }
        """
    }

    // MARK: - src/app/page.tsx

    public static func pageTSX(projectName: String) -> String {
        """
        export default function HomePage() {
          return (
            <main className="flex min-h-screen items-center justify-center px-6">
              <div className="text-center space-y-4">
                <h1 className="text-4xl font-bold tracking-tight">Bonjour {`\(projectName)`}</h1>
                <p className="text-neutral-600">Scaffolded by MIND. Ship something great.</p>
              </div>
            </main>
          )
        }
        """
    }

    // MARK: - src/app/globals.css

    public static func globalsCSS() -> String {
        """
        @import 'tailwindcss';

        :root {
          --background: #ffffff;
          --foreground: #0a0a0a;
        }

        @media (prefers-color-scheme: dark) {
          :root {
            --background: #0a0a0a;
            --foreground: #ededed;
          }
        }

        body {
          color: var(--foreground);
          background: var(--background);
          font-feature-settings: 'rlig' 1, 'calt' 1;
        }
        """
    }

    // MARK: - src/app/api/contact/route.ts

    /// Contact form handler. Zod-validated, Resend-powered, rate-
    /// limited, and pre-wired to `@mind/lead-webhook` so every
    /// inbound submission lands in Mehdi's MIND cockpit before the
    /// transactional email is sent — guarantees the lead is captured
    /// even when Resend errors.
    public static func contactRouteTS() -> String {
        """
        import { NextRequest, NextResponse } from 'next/server'
        import { z } from 'zod'
        import { Resend } from 'resend'
        import { sendLeadToMIND } from '@mind/lead-webhook'
        import { rateLimit } from '@/lib/rate-limit'

        export const runtime = 'nodejs'
        export const dynamic = 'force-dynamic'

        const ContactSchema = z.object({
          name: z.string().min(1).max(120),
          email: z.string().email().max(254),
          message: z.string().min(1).max(5000),
          source: z.string().optional(),
        })

        export async function POST(req: NextRequest) {
          const ip = req.headers.get('x-forwarded-for') ?? 'anonymous'
          const limited = await rateLimit({ key: `contact:${ip}`, limit: 5, window: 60 })
          if (limited) {
            return NextResponse.json({ error: 'rate_limited' }, { status: 429 })
          }

          const json = await req.json().catch(() => null)
          const parsed = ContactSchema.safeParse(json)
          if (!parsed.success) {
            return NextResponse.json({ error: 'invalid_payload', issues: parsed.error.issues }, { status: 400 })
          }
          const { name, email, message, source } = parsed.data

          // 1. Forward to MIND cockpit first — never lose a lead.
          try {
            await sendLeadToMIND({
              projectID: process.env.MIND_PROJECT_ID!,
              formType: 'contact',
              contact: { name, email },
              message,
              sourceURL: source ?? req.headers.get('referer') ?? '',
              userAgent: req.headers.get('user-agent') ?? '',
              ipHash: ip,
            }, {
              endpoint: process.env.MIND_WEBHOOK_URL!,
              secret: process.env.MIND_WEBHOOK_SECRET!,
            })
          } catch (err) {
            console.error('[mind-webhook] forward failed', err)
            // We still try to send the email so the user gets a reply.
          }

          // 2. Send the transactional email via Resend.
          try {
            const resend = new Resend(process.env.RESEND_API_KEY)
            await resend.emails.send({
              from: process.env.RESEND_FROM_ADDRESS!,
              to: process.env.RESEND_TO_ADDRESS!,
              replyTo: email,
              subject: `Contact — ${name}`,
              text: `From: ${name} <${email}>\\n\\n${message}`,
            })
          } catch (err) {
            console.error('[resend] send failed', err)
            return NextResponse.json({ error: 'email_failed' }, { status: 502 })
          }

          return NextResponse.json({ ok: true })
        }
        """
    }

    // MARK: - src/lib/email.ts

    public static func emailLibTS() -> String {
        """
        import { Resend } from 'resend'

        export const resend = new Resend(process.env.RESEND_API_KEY)

        export interface EmailPayload {
          from: string
          to: string
          replyTo?: string
          subject: string
          text: string
        }

        export async function sendEmail(payload: EmailPayload) {
          return resend.emails.send(payload)
        }
        """
    }

    // MARK: - src/lib/rate-limit.ts

    public static func rateLimitLibTS() -> String {
        """
        // In-memory rate limiter (process-local). Fine for low-traffic
        // marketing sites; swap for Upstash Redis on retainer clients.

        const buckets = new Map<string, { count: number; expiresAt: number }>()

        export interface RateLimitOptions {
          key: string
          limit: number
          window: number // seconds
        }

        export async function rateLimit(opts: RateLimitOptions): Promise<boolean> {
          const now = Date.now()
          const bucket = buckets.get(opts.key)
          if (!bucket || bucket.expiresAt < now) {
            buckets.set(opts.key, { count: 1, expiresAt: now + opts.window * 1000 })
            return false
          }
          bucket.count += 1
          if (bucket.count > opts.limit) {
            return true
          }
          return false
        }
        """
    }

    // MARK: - src/app/robots.ts

    public static func robotsTS(host: String) -> String {
        """
        import type { MetadataRoute } from 'next'

        export default function robots(): MetadataRoute.Robots {
          return {
            rules: [{ userAgent: '*', allow: '/' }],
            sitemap: 'https://\(host)/sitemap.xml',
          }
        }
        """
    }

    // MARK: - src/app/sitemap.ts

    public static func sitemapTS(host: String) -> String {
        """
        import type { MetadataRoute } from 'next'

        export default function sitemap(): MetadataRoute.Sitemap {
          return [
            {
              url: 'https://\(host)',
              lastModified: new Date(),
              changeFrequency: 'weekly',
              priority: 1,
            },
          ]
        }
        """
    }

    // MARK: - vercel.json

    /// Security headers Mehdi's lighthouse score depends on, plus
    /// the `cdg1` region pin (Paris — every Numelite client is in
    /// France) and the main-only deploy gate.
    public static func vercelJSON() -> String {
        """
        {
          "$schema": "https://openapi.vercel.sh/vercel.json",
          "regions": ["cdg1"],
          "git": {
            "deploymentEnabled": {
              "main": true
            }
          },
          "headers": [
            {
              "source": "/(.*)",
              "headers": [
                { "key": "X-Frame-Options", "value": "SAMEORIGIN" },
                { "key": "X-Content-Type-Options", "value": "nosniff" },
                { "key": "Referrer-Policy", "value": "strict-origin-when-cross-origin" },
                { "key": "Permissions-Policy", "value": "camera=(), microphone=(), geolocation=()" },
                { "key": "Strict-Transport-Security", "value": "max-age=63072000; includeSubDomains; preload" }
              ]
            }
          ]
        }
        """
    }

    // MARK: - .env.example

    public static func envExample(includeStripe: Bool) -> String {
        var lines: [String] = [
            "# Resend — transactional email",
            "RESEND_API_KEY=re_xxx",
            "RESEND_FROM_ADDRESS=\"Project <hello@example.com>\"",
            "RESEND_TO_ADDRESS=mehdi@numelite.fr",
            "",
            "# Database (Drizzle / Supabase / Prisma — adapt to your stack)",
            "DATABASE_URL=postgres://user:pass@host:5432/db",
            "",
            "# MIND cockpit lead webhook",
            "MIND_PROJECT_ID=00000000-0000-0000-0000-000000000000",
            "MIND_WEBHOOK_URL=https://lead-webhook.mind.workers.dev/v1/leads",
            "MIND_WEBHOOK_SECRET=replace-with-openssl-rand-hex-32",
            "",
            "# Analytics",
            "NEXT_PUBLIC_PLAUSIBLE_DOMAIN=example.com",
        ]
        if includeStripe {
            lines.append("")
            lines.append("# Stripe")
            lines.append("STRIPE_SECRET_KEY=sk_test_xxx")
            lines.append("STRIPE_WEBHOOK_SECRET=whsec_xxx")
            lines.append("NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY=pk_test_xxx")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - .gitignore

    public static func gitignore() -> String {
        """
        # Dependencies
        node_modules
        .pnp
        .pnp.js
        .yarn/install-state.gz

        # Next.js
        .next/
        out/
        build/
        dist/

        # Production
        *.tsbuildinfo
        next-env.d.ts

        # Env
        .env
        .env*.local
        .env.production
        .env.development

        # Misc
        .DS_Store
        *.pem
        coverage/

        # Debug
        npm-debug.log*
        yarn-debug.log*
        yarn-error.log*

        # Vercel
        .vercel
        """
    }

    // MARK: - .cursorrules

    public static func cursorrules(projectName: String) -> String {
        """
        # \(projectName) — Cursor / Claude Code rules

        ## Stack
        - Next.js 15 (app router), React 19, TypeScript strict.
        - Tailwind 4 — no SCSS, no CSS modules.
        - Resend for transactional email.
        - Zod for runtime validation.

        ## Conventions
        - Server components by default; mark client islands with `'use client'`.
        - Co-locate Zod schemas with the route handler.
        - Every `/api/*` route handler returns a `NextResponse.json(...)`.
        - Every external POST is rate-limited via `src/lib/rate-limit.ts`.
        - Every form submission forwards to the MIND cockpit before
          sending the transactional email — never lose a lead.

        ## Forbidden
        - No `any`, no `@ts-ignore`. Prefer `unknown` + a narrow guard.
        - No client-side fetch of secrets. Pass through a route handler.
        - No inline `<style>` blocks. Tailwind only.
        """
    }

    // MARK: - README.md

    public static func readme(projectName: String, host: String) -> String {
        """
        # \(projectName)

        Scaffolded by **MIND**. Production target: `https://\(host)`.

        ## Local

        ```bash
        cp .env.example .env.local
        npm install
        npm run dev
        ```

        ## Deploy

        ```bash
        vercel link
        vercel --prod
        ```

        ## Lead capture

        Forms submit to `POST /api/contact` which:

        1. Forwards the payload to the MIND cockpit via `@mind/lead-webhook`.
        2. Sends a transactional email via Resend.

        Configure `MIND_PROJECT_ID`, `MIND_WEBHOOK_URL`, and
        `MIND_WEBHOOK_SECRET` in your `.env.local`. The MIND iPhone
        app surfaces every lead in the Aujourd'hui inbox within
        seconds.
        """
    }

    // MARK: - Admin skeleton (optional bundle)

    public static func adminPageTSX() -> String {
        """
        export const dynamic = 'force-dynamic'

        export default function AdminDashboard() {
          return (
            <main className="p-8 space-y-6">
              <header>
                <h1 className="text-3xl font-bold">Dashboard</h1>
                <p className="text-neutral-600">Backoffice scaffolded by MIND.</p>
              </header>
              <section className="grid grid-cols-1 md:grid-cols-3 gap-4">
                <article className="rounded-2xl border p-4">Leads</article>
                <article className="rounded-2xl border p-4">Content</article>
                <article className="rounded-2xl border p-4">Settings</article>
              </section>
            </main>
          )
        }
        """
    }

    public static func adminAuthTS() -> String {
        """
        import bcrypt from 'bcryptjs'
        import { SignJWT, jwtVerify } from 'jose'

        const SECRET = new TextEncoder().encode(process.env.ADMIN_AUTH_SECRET ?? 'change-me')

        export async function hashPassword(plain: string): Promise<string> {
          return bcrypt.hash(plain, 12)
        }

        export async function verifyPassword(plain: string, hashed: string): Promise<boolean> {
          return bcrypt.compare(plain, hashed)
        }

        export async function signSession(userID: string): Promise<string> {
          return new SignJWT({ sub: userID })
            .setProtectedHeader({ alg: 'HS256' })
            .setIssuedAt()
            .setExpirationTime('7d')
            .sign(SECRET)
        }

        export async function verifySession(token: string): Promise<string | null> {
          try {
            const { payload } = await jwtVerify(token, SECRET)
            return (payload.sub as string | undefined) ?? null
          } catch {
            return null
          }
        }
        """
    }

    // MARK: - Blog skeleton (optional bundle)

    public static func blogSamplePostMDX() -> String {
        """
        ---
        title: Premier article
        date: 2026-05-20
        excerpt: Article exemple scaffolded by MIND.
        ---

        Bienvenue sur le blog. Cette page rend du **MDX** via
        `next-mdx-remote`. Édite ce fichier dans `content/blog/` pour
        publier un nouvel article.
        """
    }

    // MARK: - i18n skeleton (optional bundle)

    public static func nextIntlConfigTS() -> String {
        """
        import { getRequestConfig } from 'next-intl/server'

        export default getRequestConfig(async ({ locale }) => ({
          messages: (await import(`./messages/${locale}.json`)).default,
        }))
        """
    }

    public static func i18nMessagesFR() -> String {
        """
        {
          "home": {
            "title": "Bienvenue",
            "subtitle": "Scaffolded par MIND"
          }
        }
        """
    }

    public static func i18nMessagesEN() -> String {
        """
        {
          "home": {
            "title": "Welcome",
            "subtitle": "Scaffolded by MIND"
          }
        }
        """
    }

    // MARK: - Stripe skeleton (optional bundle)

    public static func stripeConfigTS() -> String {
        """
        import Stripe from 'stripe'

        export const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!, {
          apiVersion: '2024-11-20.acacia',
        })
        """
    }

    public static func stripeWebhookRouteTS() -> String {
        """
        import { NextRequest, NextResponse } from 'next/server'
        import { stripe } from '@/stripe.config'

        export const runtime = 'nodejs'

        export async function POST(req: NextRequest) {
          const sig = req.headers.get('stripe-signature')
          if (!sig) return NextResponse.json({ error: 'missing_signature' }, { status: 400 })

          const body = await req.text()
          try {
            const event = stripe.webhooks.constructEvent(body, sig, process.env.STRIPE_WEBHOOK_SECRET!)
            // Handle event types here.
            console.log('[stripe]', event.type)
            return NextResponse.json({ received: true })
          } catch (err) {
            console.error('[stripe] webhook verify failed', err)
            return NextResponse.json({ error: 'invalid_signature' }, { status: 400 })
          }
        }
        """
    }
}
