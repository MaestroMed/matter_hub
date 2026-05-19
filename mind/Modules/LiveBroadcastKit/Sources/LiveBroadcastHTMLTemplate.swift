import Foundation

/// Returns the static `index.html` template written next to every
/// `state.json` snapshot.
///
/// The template is **single-file** — inline CSS + inline vanilla JS,
/// no `<link>` to any sibling asset — so Mehdi can drop the folder
/// onto Vercel / Cloudflare Pages / `npx serve` / `python -m
/// http.server` with no further hand-wiring. The only external
/// network request the page makes is `fetch('./state.json')` every
/// 800 ms, which works under any hosting because the path is relative.
///
/// Design language: **Liquid Glass dark cinematic**. Iris (`#6B5DD3`)
/// accent, navy-to-black radial-gradient backdrop, frosted
/// `backdrop-filter` cards, Apple system font stack falling back to
/// Inter on Linux/Windows clients. Honours `prefers-reduced-motion`
/// for the typewriter and pulse animations.
public enum LiveBroadcastHTMLTemplate {

    /// Build the template body. Pure — no `Date()` reads, no FS reads,
    /// no I/O. Same input → same bytes, which the determinism test
    /// asserts.
    ///
    /// `clientName` and `host` are baked into the initial HTML so the
    /// page renders meaningful content even before the first
    /// `fetch('./state.json')` resolves; once the JSON lands, the
    /// `render` JS function overwrites everything from the wire data.
    public static func render(
        clientName: String,
        host: String
    ) -> String {
        let escapedClient = htmlEscape(clientName)
        let escapedHost = htmlEscape(host)
        return """
        <!doctype html>
        <html lang="fr">
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
          <meta name="theme-color" content="#0a0a14" />
          <meta name="referrer" content="no-referrer" />
          <meta name="robots" content="noindex" />
          <title>Audit live · \(escapedClient) — MIND</title>
          <link rel="preconnect" href="https://fonts.googleapis.com" />
          <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
          <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&family=JetBrains+Mono:wght@400;600&display=swap" />
          <style>
        \(inlineCSS)
          </style>
        </head>
        <body>
          <div class="bg-layer bg-grain" aria-hidden="true"></div>
          <div class="bg-layer bg-gradient" aria-hidden="true"></div>
          <div class="bg-layer bg-noise" aria-hidden="true"></div>

          <main class="stage" id="stage">
            <header class="hero" id="hero">
              <div class="status-pill" id="statusPill">
                <span class="status-pill__dot"></span>
                <span class="status-pill__label" id="statusPillLabel">En attente</span>
              </div>
              <h1 class="hero__client" id="clientName">\(escapedClient)</h1>
              <p class="hero__host" id="hostLine">\(escapedHost)</p>
              <p class="hero__byline">Audit MIND — diffusion en direct</p>
            </header>

            <section class="card probes-card" aria-label="Sondes">
              <div class="card__header">
                <h2 class="card__title">14 sondes</h2>
                <span class="card__meta" id="probesMeta">— / —</span>
              </div>
              <div class="probes-grid" id="probesGrid">
                <!-- probe cards injected by render() -->
              </div>
            </section>

            <section class="card scoring-card" id="scoringCard" hidden>
              <div class="card__header">
                <h2 class="card__title">Scoring</h2>
                <span class="card__meta" id="overallLabel"></span>
              </div>
              <div class="gauges" id="gauges">
                <!-- 5 axis gauges injected by render() -->
              </div>
            </section>

            <section class="card synthesis-card" id="synthesisCard" hidden>
              <div class="card__header">
                <h2 class="card__title">Synthèse</h2>
              </div>
              <article class="synthesis" id="synthesis"></article>
            </section>

            <section class="card cta-card" id="ctaCard" hidden>
              <div class="cta-card__inner">
                <h2 class="cta-card__title">Audit terminé.</h2>
                <p class="cta-card__sub">Discutons des prochaines étapes.</p>
                <a class="cta-card__btn" id="ctaButton" href="mailto:hello@mehdi.app">Discuter avec Mehdi</a>
              </div>
            </section>

            <footer class="footer">
              <span>Diffusé par <strong>MIND</strong></span>
              <span class="footer__sep">·</span>
              <span id="updatedAt">Mise à jour…</span>
            </footer>
          </main>

          <noscript>
            <p style="color:#fff;padding:24px;text-align:center;">
              JavaScript est nécessaire pour suivre l'audit en direct.
            </p>
          </noscript>

          <script>
        \(inlineJS)
          </script>
        </body>
        </html>
        """
    }

    /// Hard ceiling on the rendered template size — the file-size
    /// test asserts the rendered body stays under this budget. Pinned
    /// at 50 KB per ULTRAPLAN acceptance.
    public static let maxBytes: Int = 50_000

    // MARK: - HTML helpers

    /// Bare-minimum HTML escaping for the static interpolated values
    /// (client name + host) that flow into the template body before
    /// the first JSON refresh. Belt-and-braces — the template only
    /// inlines values the AuditSheet validated, but a Stripe-shaped
    /// client name like `<script>alert(1)</script>` should still
    /// render as text rather than execute.
    private static func htmlEscape(_ input: String) -> String {
        var out = ""
        out.reserveCapacity(input.count)
        for ch in input {
            switch ch {
            case "&": out.append("&amp;")
            case "<": out.append("&lt;")
            case ">": out.append("&gt;")
            case "\"": out.append("&quot;")
            case "'": out.append("&#39;")
            default: out.append(ch)
            }
        }
        return out
    }

    // MARK: - Inline CSS

    /// Crafted as a single multiline string so the template stays
    /// single-file. Token discipline: `#6B5DD3` iris, `#0a0a14` ink,
    /// `#16162a` navy. No JS runtime hooks here — just static styling.
    private static let inlineCSS: String = """
              :root {
                color-scheme: dark;
                --iris: #6B5DD3;
                --iris-soft: rgba(107, 93, 211, 0.18);
                --iris-strong: #8C7DF3;
                --ink: #0a0a14;
                --ink-2: #16162a;
                --fg: rgba(255, 255, 255, 0.92);
                --fg-dim: rgba(255, 255, 255, 0.62);
                --fg-mute: rgba(255, 255, 255, 0.40);
                --green: #34d399;
                --red: #f87171;
                --yellow: #fbbf24;
                --grey: rgba(255, 255, 255, 0.18);
                --glass: rgba(255, 255, 255, 0.04);
                --glass-stroke: rgba(255, 255, 255, 0.10);
                --radius-lg: 24px;
                --radius-md: 16px;
                --radius-sm: 12px;
                --shadow-soft: 0 30px 60px rgba(0,0,0,0.45);
                --font-sans: -apple-system, BlinkMacSystemFont, 'SF Pro Display', 'SF Pro Text', 'Inter', system-ui, sans-serif;
                --font-mono: 'JetBrains Mono', SFMono-Regular, Menlo, monospace;
                --ease: cubic-bezier(0.22, 1, 0.36, 1);
              }
              * { box-sizing: border-box; }
              html, body {
                margin: 0;
                padding: 0;
                background: var(--ink);
                color: var(--fg);
                font-family: var(--font-sans);
                font-feature-settings: "ss01", "cv11";
                -webkit-font-smoothing: antialiased;
                min-height: 100vh;
                min-height: 100dvh;
              }
              body { overflow-x: hidden; }

              .bg-layer { position: fixed; inset: 0; pointer-events: none; }
              .bg-gradient {
                background:
                  radial-gradient(1200px 600px at 20% -10%, rgba(107,93,211,0.45), transparent 60%),
                  radial-gradient(900px 500px at 110% 10%, rgba(54, 84, 220, 0.35), transparent 65%),
                  linear-gradient(180deg, #0a0a14 0%, #050510 100%);
                z-index: 0;
              }
              .bg-grain { z-index: 1; opacity: 0.08; mix-blend-mode: overlay; background-image: radial-gradient(rgba(255,255,255,0.7) 1px, transparent 1px); background-size: 3px 3px; }
              .bg-noise {
                z-index: 1;
                opacity: 0.07;
                background-image: url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='160' height='160'><filter id='n'><feTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='2' stitchTiles='stitch'/></filter><rect width='100%' height='100%' filter='url(%23n)' opacity='0.6'/></svg>");
              }

              .stage {
                position: relative;
                z-index: 2;
                max-width: 1140px;
                margin: 0 auto;
                padding: clamp(24px, 4vw, 56px) clamp(16px, 4vw, 40px) 96px;
                display: flex;
                flex-direction: column;
                gap: 28px;
              }

              .hero { text-align: center; padding: clamp(16px, 4vw, 40px) 0 8px; }
              .hero__client {
                font-size: clamp(48px, 8vw, 96px);
                font-weight: 800;
                letter-spacing: -0.04em;
                line-height: 1.05;
                margin: 16px 0 12px;
                background: linear-gradient(180deg, #ffffff 0%, rgba(255,255,255,0.72) 100%);
                -webkit-background-clip: text;
                background-clip: text;
                color: transparent;
              }
              .hero__host {
                font-family: var(--font-mono);
                font-size: clamp(14px, 1.4vw, 18px);
                color: var(--fg-dim);
                margin: 0 0 4px;
                letter-spacing: 0.02em;
              }
              .hero__byline {
                font-size: 13px;
                color: var(--fg-mute);
                letter-spacing: 0.18em;
                text-transform: uppercase;
                margin: 12px 0 0;
              }

              .status-pill {
                display: inline-flex;
                align-items: center;
                gap: 10px;
                padding: 8px 16px;
                border-radius: 999px;
                background: var(--glass);
                border: 1px solid var(--glass-stroke);
                -webkit-backdrop-filter: blur(20px);
                backdrop-filter: blur(20px);
                font-size: 12px;
                font-weight: 600;
                text-transform: uppercase;
                letter-spacing: 0.18em;
                color: var(--fg-dim);
              }
              .status-pill__dot {
                width: 8px;
                height: 8px;
                border-radius: 999px;
                background: var(--iris);
                box-shadow: 0 0 0 0 var(--iris);
                animation: pulse 1.8s var(--ease) infinite;
              }
              .status-pill.is-done .status-pill__dot { background: var(--green); animation: none; }
              .status-pill.is-failed .status-pill__dot { background: var(--red); animation: none; }
              .status-pill.is-done .status-pill__label,
              .status-pill.is-failed .status-pill__label { color: var(--fg); }

              @keyframes pulse {
                0%   { box-shadow: 0 0 0 0 rgba(107,93,211,0.6); }
                70%  { box-shadow: 0 0 0 14px rgba(107,93,211,0.0); }
                100% { box-shadow: 0 0 0 0 rgba(107,93,211,0.0); }
              }
              @media (prefers-reduced-motion: reduce) {
                .status-pill__dot { animation: none; }
              }

              .card {
                position: relative;
                background: var(--glass);
                border: 1px solid var(--glass-stroke);
                border-radius: var(--radius-lg);
                padding: clamp(20px, 3vw, 32px);
                -webkit-backdrop-filter: blur(28px);
                backdrop-filter: blur(28px);
                box-shadow: var(--shadow-soft);
              }
              .card__header {
                display: flex;
                align-items: baseline;
                justify-content: space-between;
                margin-bottom: 20px;
              }
              .card__title {
                font-size: 13px;
                margin: 0;
                font-weight: 600;
                letter-spacing: 0.18em;
                color: var(--fg-mute);
                text-transform: uppercase;
              }
              .card__meta {
                font-family: var(--font-mono);
                font-size: 12px;
                color: var(--fg-dim);
              }

              .probes-grid {
                display: grid;
                grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
                gap: 12px;
              }
              .probe {
                position: relative;
                display: flex;
                flex-direction: column;
                gap: 8px;
                padding: 16px 14px;
                border-radius: var(--radius-md);
                background: rgba(255,255,255,0.025);
                border: 1px solid rgba(255,255,255,0.06);
                transition: background 0.45s var(--ease), border-color 0.45s var(--ease), transform 0.6s var(--ease);
              }
              .probe[data-state="ok"] {
                background: linear-gradient(180deg, rgba(52,211,153,0.10), rgba(52,211,153,0.04));
                border-color: rgba(52,211,153,0.35);
              }
              .probe[data-state="failed"] {
                background: linear-gradient(180deg, rgba(248,113,113,0.12), rgba(248,113,113,0.04));
                border-color: rgba(248,113,113,0.40);
              }
              .probe[data-state="running"] {
                background: linear-gradient(180deg, rgba(107,93,211,0.18), rgba(107,93,211,0.04));
                border-color: rgba(107,93,211,0.55);
              }
              .probe__top {
                display: flex;
                align-items: center;
                justify-content: space-between;
              }
              .probe__label {
                font-size: 13px;
                font-weight: 600;
                color: var(--fg);
                letter-spacing: -0.01em;
              }
              .probe__state {
                display: inline-flex;
                align-items: center;
                justify-content: center;
                width: 22px;
                height: 22px;
                border-radius: 999px;
                background: var(--grey);
                color: var(--ink);
                font-size: 11px;
                font-weight: 700;
              }
              .probe[data-state="ok"] .probe__state    { background: var(--green); color: #042b1d; }
              .probe[data-state="failed"] .probe__state { background: var(--red);   color: #2c0808; }
              .probe[data-state="running"] .probe__state {
                background: transparent;
                border: 2px solid var(--iris-strong);
                border-top-color: transparent;
                animation: spin 0.9s linear infinite;
              }
              @media (prefers-reduced-motion: reduce) {
                .probe[data-state="running"] .probe__state { animation: none; }
              }
              @keyframes spin { to { transform: rotate(360deg); } }

              .probe__meta {
                font-family: var(--font-mono);
                font-size: 11px;
                color: var(--fg-mute);
              }
              .probe__error {
                font-size: 11px;
                color: var(--red);
                opacity: 0.85;
              }

              .gauges {
                display: grid;
                grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
                gap: 16px;
              }
              .gauge {
                display: flex;
                flex-direction: column;
                align-items: center;
                gap: 6px;
              }
              .gauge__svg { width: 110px; height: 110px; transform: rotate(-90deg); }
              .gauge__track { stroke: rgba(255,255,255,0.08); }
              .gauge__bar {
                stroke: var(--iris-strong);
                stroke-linecap: round;
                transition: stroke-dashoffset 0.9s var(--ease), stroke 0.6s var(--ease);
              }
              .gauge[data-tone="green"] .gauge__bar { stroke: var(--green); }
              .gauge[data-tone="orange"] .gauge__bar { stroke: var(--yellow); }
              .gauge[data-tone="red"] .gauge__bar { stroke: var(--red); }
              .gauge__pct {
                position: relative;
                margin-top: -78px;
                font-size: 24px;
                font-weight: 700;
                font-feature-settings: "tnum";
              }
              .gauge__label {
                font-size: 11px;
                font-weight: 600;
                color: var(--fg-dim);
                text-transform: uppercase;
                letter-spacing: 0.12em;
              }

              .synthesis {
                font-size: 15px;
                line-height: 1.65;
                color: var(--fg);
                white-space: pre-wrap;
                font-family: var(--font-sans);
              }
              .synthesis__caret {
                display: inline-block;
                width: 8px;
                height: 18px;
                margin-left: 2px;
                background: var(--iris-strong);
                vertical-align: -3px;
                animation: blink 1s steps(2) infinite;
              }
              @keyframes blink { 50% { opacity: 0; } }
              @media (prefers-reduced-motion: reduce) {
                .synthesis__caret { animation: none; }
              }

              .cta-card {
                background: linear-gradient(135deg, rgba(107,93,211,0.32), rgba(28,28,60,0.85));
                border-color: rgba(107,93,211,0.45);
                text-align: center;
              }
              .cta-card__title {
                margin: 0 0 8px;
                font-size: clamp(24px, 3vw, 36px);
                font-weight: 700;
                letter-spacing: -0.02em;
              }
              .cta-card__sub { margin: 0 0 18px; color: var(--fg-dim); }
              .cta-card__btn {
                display: inline-block;
                padding: 14px 28px;
                border-radius: 999px;
                background: #fff;
                color: var(--ink);
                font-weight: 700;
                text-decoration: none;
                transition: transform 0.4s var(--ease), box-shadow 0.4s var(--ease);
              }
              .cta-card__btn:hover { transform: translateY(-2px); box-shadow: 0 12px 28px rgba(0,0,0,0.35); }

              .footer {
                text-align: center;
                font-size: 12px;
                color: var(--fg-mute);
                margin-top: 4px;
              }
              .footer__sep { margin: 0 6px; }
        """

    // MARK: - Inline JS

    /// Vanilla JS — no framework, no transpilation, no bundler. The
    /// only contract this script knows is the JSON shape produced by
    /// `LiveBroadcastState.canonicalEncoder`. If the wire shape ever
    /// changes, both this script and the `LiveBroadcastWriter` move
    /// together.
    private static let inlineJS: String = """
              const STATE_URL = './state.json';
              const POLL_INTERVAL_MS = 800;

              const PROBE_LABELS = {
                pageSpeed: 'PageSpeed', security: 'Sécurité', email: 'Email DNS',
                domain: 'Domaine', mobile: 'App iOS', schema: 'Schema.org',
                openGraph: 'OpenGraph', crawlability: 'Crawlability',
                compliance: 'Compliance', analytics: 'Analytics',
                payment: 'Paiement', cdn: 'CDN', trust: 'Trustpilot'
              };
              const PROBE_ORDER = [
                'pageSpeed','security','email','domain','mobile','schema','openGraph',
                'crawlability','compliance','analytics','payment','cdn','trust'
              ];
              const SCORE_LABELS = {
                performance: 'Performance', seo: 'SEO', security: 'Sécurité',
                brand: 'Brand', mobile: 'Mobile'
              };

              let lastSynthesisLength = 0;
              let lastPhase = '';
              let lastStateHash = '';

              function escapeHTML(s) {
                if (s == null) return '';
                return String(s)
                  .replace(/&/g, '&amp;')
                  .replace(/</g, '&lt;')
                  .replace(/>/g, '&gt;')
                  .replace(/"/g, '&quot;')
                  .replace(/'/g, '&#39;');
              }

              function gaugeTone(value) {
                if (value >= 80) return 'green';
                if (value >= 50) return 'orange';
                return 'red';
              }

              function renderProbes(state) {
                const grid = document.getElementById('probesGrid');
                const probesByKind = {};
                (state.probes || []).forEach(p => { probesByKind[p.kind] = p; });

                let ok = 0, failed = 0;
                let html = '';
                for (const kind of PROBE_ORDER) {
                  const p = probesByKind[kind] || { kind, state: 'pending' };
                  if (p.state === 'ok') ok++;
                  if (p.state === 'failed') failed++;
                  const label = PROBE_LABELS[kind] || kind;
                  const stateIcon = p.state === 'ok' ? '✓'
                                  : p.state === 'failed' ? '✕'
                                  : p.state === 'running' ? '' : '·';
                  const meta = p.durationMs != null && p.state === 'ok' ? (p.durationMs + ' ms') : '';
                  const errorLine = p.error ? '<div class="probe__error">' + escapeHTML(p.error) + '</div>' : '';
                  html += '<div class="probe" data-state="' + escapeHTML(p.state) + '" data-kind="' + escapeHTML(kind) + '">'
                       +   '<div class="probe__top">'
                       +     '<span class="probe__label">' + escapeHTML(label) + '</span>'
                       +     '<span class="probe__state" aria-label="' + escapeHTML(p.state) + '">' + stateIcon + '</span>'
                       +   '</div>'
                       +   (meta ? '<div class="probe__meta">' + escapeHTML(meta) + '</div>' : '')
                       +   errorLine
                       + '</div>';
                }
                grid.innerHTML = html;
                document.getElementById('probesMeta').textContent =
                  ok + ' OK · ' + failed + ' erreurs · ' + PROBE_ORDER.length + ' au total';
              }

              function renderScoring(state) {
                const card = document.getElementById('scoringCard');
                if (!state.scoring) { card.hidden = true; return; }
                card.hidden = false;
                document.getElementById('overallLabel').textContent =
                  'Score global ' + state.scoring.overall + ' / 100';
                const axes = ['performance','seo','security','brand','mobile'];
                const gauges = document.getElementById('gauges');
                const circumference = 2 * Math.PI * 42;
                let html = '';
                for (const axis of axes) {
                  const value = state.scoring[axis] != null ? state.scoring[axis] : 0;
                  const tone = gaugeTone(value);
                  const offset = circumference * (1 - value / 100);
                  html += '<div class="gauge" data-tone="' + tone + '">'
                       +   '<svg class="gauge__svg" viewBox="0 0 100 100">'
                       +     '<circle class="gauge__track" cx="50" cy="50" r="42" fill="none" stroke-width="8"/>'
                       +     '<circle class="gauge__bar" cx="50" cy="50" r="42" fill="none" stroke-width="8"'
                       +       ' stroke-dasharray="' + circumference + '"'
                       +       ' stroke-dashoffset="' + offset + '"/>'
                       +   '</svg>'
                       +   '<div class="gauge__pct">' + value + '</div>'
                       +   '<div class="gauge__label">' + escapeHTML(SCORE_LABELS[axis] || axis) + '</div>'
                       + '</div>';
                }
                gauges.innerHTML = html;
              }

              function renderSynthesis(state) {
                const card = document.getElementById('synthesisCard');
                const target = document.getElementById('synthesis');
                if (!state.synthesis) { card.hidden = true; return; }
                card.hidden = false;
                const full = state.synthesis;
                const isGrowing = full.length > lastSynthesisLength;
                lastSynthesisLength = full.length;
                const caret = state.phase === 'synthesizing' ? '<span class="synthesis__caret" aria-hidden="true"></span>' : '';
                target.innerHTML = escapeHTML(full) + caret;
                if (isGrowing) {
                  target.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
                }
              }

              function renderCTA(state) {
                const card = document.getElementById('ctaCard');
                if (state.phase !== 'completed') { card.hidden = true; return; }
                card.hidden = false;
              }

              function renderStatusPill(state) {
                const pill = document.getElementById('statusPill');
                const label = document.getElementById('statusPillLabel');
                pill.classList.remove('is-done', 'is-failed');
                let text = 'En direct';
                if (state.phase === 'probing') text = 'Sondes en cours';
                else if (state.phase === 'synthesizing') text = 'Synthèse en cours';
                else if (state.phase === 'completed') { text = 'Terminé'; pill.classList.add('is-done'); }
                else if (state.phase === 'failed') { text = 'Échec'; pill.classList.add('is-failed'); }
                label.textContent = text;
              }

              function renderUpdated(state) {
                const el = document.getElementById('updatedAt');
                try {
                  const d = new Date(state.updatedAt);
                  el.textContent = 'Mis à jour à ' + d.toLocaleTimeString('fr-FR');
                } catch (e) { el.textContent = ''; }
              }

              function render(state) {
                if (!state) return;
                document.getElementById('clientName').textContent = state.clientName || '';
                document.getElementById('hostLine').textContent = state.host || '';
                renderStatusPill(state);
                renderProbes(state);
                renderScoring(state);
                renderSynthesis(state);
                renderCTA(state);
                renderUpdated(state);
                lastPhase = state.phase;
              }

              async function poll() {
                try {
                  const res = await fetch(STATE_URL, { cache: 'no-store' });
                  if (!res.ok) throw new Error('HTTP ' + res.status);
                  const state = await res.json();
                  const hash = (state.updatedAt || '') + ':' + (state.synthesis ? state.synthesis.length : 0)
                             + ':' + (state.probes ? state.probes.map(p => p.state).join(',') : '');
                  if (hash !== lastStateHash) {
                    lastStateHash = hash;
                    render(state);
                  }
                } catch (e) {
                  // Network blip is non-fatal — the next poll tick retries.
                }
              }

              renderProbes({ probes: [] });
              poll();
              setInterval(poll, POLL_INTERVAL_MS);
        """
}
