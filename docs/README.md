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

Ruby pin lives in `docs/.tool-versions` (`ruby 3.3.4`) so [asdf] activates
the right version automatically the moment you `cd docs`. We need 3.3.x
specifically because the `github-pages` gem still pins Jekyll 3.10 /
Liquid 4.0, which call `Object#tainted?` — removed in Ruby 3.2 and
absent from macOS Homebrew's Ruby 4.x. GitHub Pages itself runs on
Ruby 3.3, so local and production stay aligned.

### One-time bootstrap

If you already have asdf and its Ruby plugin's build deps, this is the
whole story:

```sh
make docs-bootstrap
```

That target asks asdf to install the plugin (idempotent), reads
`docs/.tool-versions`, installs Ruby 3.3.4, and runs `bundle install` into
`docs/vendor/bundle/` (gitignored).

If you don't have asdf yet:

```sh
brew install asdf
# Add asdf to your shell once — see https://asdf-vm.com/guide/getting-started.html
echo '. /opt/homebrew/opt/asdf/libexec/asdf.sh' >> ~/.zshrc
exec zsh

# Build deps for compiling Ruby on macOS (one-time):
brew install openssl@3 readline libyaml gmp

make docs-bootstrap
```

### Serve

From the repo root:

```sh
make docs-serve
```

Open <http://127.0.0.1:4000/>. NL lives at <http://127.0.0.1:4000/nl/>.
The target sanity-checks the active Ruby and aborts with a pointer to
`make docs-bootstrap` if you're on the wrong version.

The Make targets prepend `~/.asdf/shims` to `PATH` so they work even when
Homebrew's Ruby sits earlier in your shell `PATH`. If you'd rather run
`bundle` / `jekyll` directly (without Make), put the shims dir first in
your own `PATH` or run them through `asdf exec` from inside `docs/`.

[asdf]: https://asdf-vm.com/

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

## Deploying to `gluwink.app`

GitHub side (one-time):

1. Settings → Pages → Source: **Deploy from a branch** → `main` / `/docs`.
2. Settings → Pages → Custom domain: **`gluwink.app`** → tick **Enforce
   HTTPS** once the certificate provisions.

DNS side (registrar):

| Record | Host | Value |
|---|---|---|
| ALIAS / ANAME | `@` | `fokkezb.github.io` |
| CNAME | `www` | `fokkezb.github.io` |

Use four `A` records to GitHub's Pages IPs as a fallback if your registrar
doesn't support ALIAS / ANAME. Latest list:
<https://docs.github.com/pages/configuring-a-custom-domain-for-your-github-pages-site/managing-a-custom-domain-for-your-github-pages-site#configuring-an-apex-domain>.

After DNS propagates (minutes to a few hours), GitHub re-issues the cert
automatically, the green check appears under Pages, and `https://gluwink.app`
serves this folder.

## App Store URL checklist (before submitting v1.0)

App Review verifies these URLs exist and return 200 in every locale:

- `https://gluwink.app/` and `https://gluwink.app/nl/` — marketing
- `https://gluwink.app/privacy/` and `https://gluwink.app/nl/privacy/`
- `https://gluwink.app/support/` and `https://gluwink.app/nl/support/`

The Medical category specifically requires Privacy + Support to be live
before submission.
