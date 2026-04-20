# GluWink marketing site (`docs/`)

Static Jekyll site served by **GitHub Pages** from the `main` branch's
`/docs` folder. No Actions workflow builds the site — Pages runs the
allowlisted Jekyll plugins on its own. Lives at **`https://gluwink.app`**
(custom domain via `docs/CNAME`).

The screenshots drift-check (`.github/workflows/screenshots-sync-check.yml`)
is a separate, small workflow that has nothing to do with the site build.

## What's where

```
docs/
├── CNAME                           gluwink.app (custom-domain marker)
├── _config.yml                     site config; flip `launched: true` at v1.0
├── Gemfile                         pinned to the github-pages gem
├── _data/
│   ├── en.yml                      EN copy (hero, sections, FAQ, meta)
│   └── nl.yml                      NL copy, identical key structure
├── _includes/
│   ├── head.html                   meta + OG/Twitter + favicons + SEO
│   ├── header.html                 brand + nav + language switcher
│   ├── footer.html                 tagline + privacy/support/github links
│   ├── cta.html                    SINGLE swap point for the primary CTA
│   └── hero-carousel.html          above-the-fold phone + auto-rotating shots
├── _layouts/
│   ├── default.html                site chrome wrapper
│   └── page.html                   prose wrapper (privacy/support)
├── index.html · privacy.html · support.html      EN at root
├── nl/index.html · nl/privacy.html · nl/support.html   NL under /nl/
├── 404.html · robots.txt
├── assets/
│   ├── css/site.css                mobile-first, dark-mode aware
│   ├── icons/                      app icon + favicons
│   └── screenshots/<locale>/       curated 4-scene deck (synced)
└── scripts/sync-screenshots.sh     copies the deck out of iOS/fastlane/
```

## Local dev

All tool pins (Ruby + `gh` + `jq`) live in [`mise.toml`](../mise.toml) at the
repo root. Ruby 3.3.x is required: the `github-pages` gem pins Jekyll 3.10 /
Liquid 4.0, which call `Object#tainted?` (removed in Ruby 3.2). GitHub Pages
itself runs on Ruby 3.3, so local matches production.

### One-time bootstrap

```sh
brew install mise
echo 'eval "$(mise activate zsh)"' >> ~/.zshrc && exec zsh

brew install openssl@3 readline libyaml gmp   # Ruby build deps (macOS)

make docs-bootstrap   # mise install + bundle install into docs/vendor/bundle/
```

### Serve

From the repo root:

```sh
make docs-serve
```

Open <http://127.0.0.1:4000/>. NL lives at <http://127.0.0.1:4000/nl/>.
The target sanity-checks the active Ruby and aborts with a pointer to
`make docs-bootstrap` if you're on the wrong version.

The Make targets call `mise exec ruby --` so they work regardless of what's
earlier in `$PATH`. To run `bundle` / `jekyll` directly: either activate mise
in your shell (`eval "$(mise activate zsh)"`, recommended — does this for
every command) or prefix one-offs with `mise exec ruby -- bundle …`.

[mise]: https://mise.jdx.dev/

### Pre-merge production check

Before merging anything that's likely to affect what GitHub Pages
serves (layout includes, plugin config, `_config.yml`, asset paths),
run a clean production build and serve the static output exactly the
way Pages will:

```sh
make docs-publish-check
```

That target runs `JEKYLL_ENV=production bundle exec jekyll build` into
`docs/_site/`, then serves the result with a vanilla
`python3 -m http.server` on <http://127.0.0.1:4001/> (different port
from `docs-serve` so both can run side-by-side). It catches issues
that `docs-serve`'s live-reload mode hides — wrong `relative_url`s,
broken Liquid in includes that only fires under the production env,
missing assets that 404 once Jekyll's dev middleware isn't proxying
them.

### Lighthouse audit

To check performance / a11y / best-practices / SEO scores against the
same production build:

```sh
make docs-audit
```

This runs Lighthouse (mobile, simulated throttling) against `/` and
`/nl/`, prints a summary table and the failing audits, and saves raw
JSON reports to `/tmp/glucwink-lh/`. It auto-builds and serves the
site if needed, or reuses an existing `:4001` listener.

Pairs with the **`site-audit`** Claude/Cursor skill — say "audit the
site" and the agent will run this, decide whether anything needs
fixing, and offer to file an issue + open a PR.

## Editing copy

All user-visible English strings live in `_data/en.yml`. All Dutch strings
live in `_data/nl.yml` with **identical keys**. Templates read the
language-specific data file based on `page.lang` — never hard-code copy in
HTML.

When the App Store description, taglines, or audience copy changes in
`AppStore/<locale>.md`, propagate matching changes here. AGENTS.md →
"Marketing Copy (keep in sync)" lists the surfaces that must stay aligned.

## Flipping the CTA at launch

The primary call-to-action has two states managed in **one place**:
`_includes/cta.html`, gated by `site.launched` in `_config.yml`.

To flip it on launch day:

1. Set `launched: true` in `_config.yml`.
2. Drop Apple's official App Store badges (downloaded from
   <https://developer.apple.com/app-store/marketing/guidelines/>) into
   `assets/badges/` as `app-store-en.svg` and `app-store-nl.svg`.
3. Update `hero.cta_app_store_url` in both `_data/en.yml` and `_data/nl.yml`
   with the real App Store URL (the one that includes the numeric `id…`
   from App Store Connect).

That's it. The pre-launch "Coming soon" branch and the post-launch badge
branch already exist in `_includes/cta.html`.

## Screenshots

Source of truth: `iOS/fastlane/screenshots/<locale>/iPhone-6.9/`, generated
by `make appstore-screenshots` from `iOS/App/ScreenshotHarness.swift`.

`make appstore-screenshots` chains into `make docs-sync-screenshots`, which
copies four scenes (`01_greenShield`, `02_redShield`, `03_widgets`,
`04_settings`) for each shipped locale into `docs/assets/screenshots/`.
The marketing site references those copies by relative URL — symlinks
don't work because GitHub Pages builds Jekyll in safe mode and silently
drops them.

CI verifies the two stay in lock-step: every PR runs
`bash docs/scripts/sync-screenshots.sh --check`. If it fails, run
`make appstore-screenshots` (or just `bash docs/scripts/sync-screenshots.sh`
if you only need to refresh the docs copy) and commit the result.

## Adding self-hosted Inter (optional)

The site currently uses the system font stack (`-apple-system`, Segoe UI,
Helvetica Neue, Arial). On iOS / macOS visitors that's San Francisco, which
matches the app's chrome perfectly and adds zero font payload. The downside
is non-Apple visitors see a slightly different typographic feel.

If you want the consistency of self-hosted Inter:

1. Drop `Inter-Regular.woff2`, `Inter-Medium.woff2`, `Inter-SemiBold.woff2`,
   `Inter-Bold.woff2` (Latin subsets, ~15 KB each) into
   `assets/fonts/inter/`.
2. Add `@font-face` declarations to the top of `assets/css/site.css` with
   `font-display: swap` and matching `font-weight` values.
3. Put `"Inter"` first in the `--font-sans` CSS variable in `:root`.

The whole change is one CSS file + 4 woff2 files; no other code touches
font loading.

## Production setup: Cloudflare in front of GitHub Pages

`gluwink.app` is served by GitHub Pages but **Cloudflare sits in front** as the
authoritative DNS *and* the TLS edge. `gluwink.com` is registered too and
301-redirects to `gluwink.app` at the Cloudflare edge — only one canonical URL
ever appears in `<link rel="canonical">`, OG tags, sitemaps, or App Store metadata.

```
Browser ─HTTPS─▶ Cloudflare edge ─HTTPS─▶ GitHub Pages (185.199.x.x)
                  ▲ adds HSTS + Always Use HTTPS
                  ▲ terminates TLS with its own cert
                  ▲ origin validated against GH's Let's Encrypt cert (Full strict)
```

The reason we proxy through Cloudflare at all is that GitHub Pages itself
[doesn't send `Strict-Transport-Security`](https://github.com/isaacs/github/issues/1249).
We get that header (and Always Use HTTPS, and an edge 301 redirect) from
Cloudflare, with the `.app` TLD's own [HSTS preload](https://hstspreload.org/)
as a third belt-and-braces layer.

### DNS (`gluwink.app` zone, on Cloudflare)

Registrar nameservers point at the two `*.ns.cloudflare.com` servers Cloudflare
assigns. Inside the zone, only four records matter:

| Type | Name | Content | Proxy |
|---|---|---|---|
| `CNAME` | `@` | `fokkezb.github.io` | Proxied (orange) |
| `CNAME` | `www` | `fokkezb.github.io` | Proxied (orange) |
| `CNAME` | `mail` | `mail.86id.nl` | DNS only (gray) |
| `TXT` | `@` | `"v=spf1 mx include:spf.86id.nl …"` | — |

Cloudflare flattens the apex `CNAME` to A records at the edge, so the four
`185.199.x.153` GH Pages addresses never need to be hand-maintained. Mail
records stay DNS-only — the proxy is HTTP-only and would silently break SMTP.

### Bringing it up from scratch

The order matters because GH Pages provisions its own Let's Encrypt cert via an
HTTP-01 challenge that **must reach GH directly**, not via Cloudflare. Run the
sequence in [#48](https://github.com/FokkeZB/GluWink/issues/48) once per fresh
setup. The summary:

1. Add the zone in Cloudflare, point the registrar at Cloudflare's nameservers,
   wait for the zone to flip from *Pending* → *Active*.
2. Add the two `CNAME` rows with the cloud **gray (DNS only)** for now.
3. In the repo, **Settings → Pages**: source = `main` `/docs`, custom domain =
   `gluwink.app`. Wait for "DNS check successful" on both the apex and `www`
   (both must be valid for the dual-SAN cert), then 5–15 min later the **Enforce
   HTTPS** checkbox un-greys. Tick it.
4. Only now: flip both `CNAME` rows to **orange (Proxied)**, then set Cloudflare
   → SSL/TLS → **Full (strict)**. Anything less than Full strict will loop or
   downgrade — Flexible in particular fights GH's HTTPS redirect to a 301 storm.
5. SSL/TLS → Edge Certificates: **Always Use HTTPS** ON, **HSTS** enabled
   (max-age 6 months → 1 year after a couple of stable weeks, includeSubDomains
   ON, Preload ON), **No-Sniff Header** ON.

### `gluwink.com` redirect zone

Same nameserver delegation. The zone has two records pointing at an
[RFC 5737](https://datatracker.ietf.org/doc/html/rfc5737) documentation IP that
exists only so Cloudflare lets us proxy it:

| Type | Name | Content | Proxy |
|---|---|---|---|
| `A` | `@` | `192.0.2.1` | Proxied |
| `A` | `www` | `192.0.2.1` | Proxied |

A **Redirect Rule** short-circuits the request at the edge before Cloudflare
ever tries to actually contact `192.0.2.1`:

- *When*: `(http.host eq "gluwink.com") or (http.host eq "www.gluwink.com")`
- *Then*: URL redirect, **Type: Dynamic** (Static rejects expressions),
  expression `concat("https://gluwink.app", http.request.uri.path)`, status
  **301**, preserve query string ON.

Same edge security as the canonical zone (Always Use HTTPS, HSTS) — partly
defense in depth, partly so HTTP clients get one redirect (`http://gluwink.com`
→ `https://gluwink.app/`) instead of two (HTTP→HTTPS, then `.com`→`.app`).

### Verifying the setup

Smoke test with a fresh public resolver so your local DNS cache can't lie to
you (Cloudflare flips are instant at the edge but local resolvers honour the
old gray-cloud TTLs longer than they should):

```sh
RES=1.1.1.1
APP_IP=$(dig @$RES +short gluwink.app | head -1)
RESOLVE="gluwink.app:443:$APP_IP"

# canonical: 200, served via Cloudflare, with HSTS
curl -sk --resolve "$RESOLVE" -I https://gluwink.app | \
  grep -iE 'HTTP/|server:|strict-transport|x-content-type-options'

# .com 301s straight to .app
for h in gluwink.com www.gluwink.com; do
  ip=$(dig @$RES +short "$h" | head -1)
  curl -sk --resolve "$h:443:$ip" -IL "https://$h/" | grep -iE 'HTTP/|location:'
done
```

Want: `HTTP/2 200`, `server: cloudflare`,
`strict-transport-security: max-age=… includeSubDomains; preload`,
`x-content-type-options: nosniff` on the canonical, and every `.com` chain
ending at `HTTP/2 200` on `https://gluwink.app/`.

### Bear traps

- **Don't delete `docs/CNAME`.** Each successful Pages build copies it back to
  the served root; if it's missing in source, GH eventually clears the
  custom-domain setting and the site starts serving on
  `fokkezb.github.io/GluWink/`, which 301s and confuses Cloudflare's cache.
- **Don't switch Cloudflare to Flexible SSL.** It would talk HTTP to GH Pages,
  GH would 301 to HTTPS, infinite loop. Always **Full (strict)**.
- **Don't proxy mail.** `mail` / `MX` / SPF / DMARC stay DNS-only. The proxy is
  HTTP-only.
- **Don't change `baseurl`.** It's empty because we serve from the apex; setting
  it to `/GluWink` (or anything else) breaks every internal link, since
  templates use `relative_url`.
- **Don't flip records to orange before the GH cert exists.** The HTTP-01
  challenge has to hit GH directly. If you proxy first, GH never finishes
  validation and you'll be stuck waiting (or hit the LE rate limit). Recovery
  is to flip back to gray, wait, retry — annoying but not destructive.

## App Store URL checklist (before submitting v1.0)

App Review verifies these URLs exist and return 200 in every locale:

- `https://gluwink.app/` and `https://gluwink.app/nl/` — marketing
- `https://gluwink.app/privacy/` and `https://gluwink.app/nl/privacy/`
- `https://gluwink.app/support/` and `https://gluwink.app/nl/support/`

The Medical category specifically requires Privacy + Support to be live
before submission.
