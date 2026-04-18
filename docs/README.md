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
│   └── screenshot-grid.html        4-up gallery
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

The `github-pages` gem pins Jekyll 3.10 / Liquid 4.0, which call
`Object#tainted?` — a method removed in Ruby 3.2. Production builds run on
GitHub's container with Ruby 3.3, so they work fine; local builds need a
matching Ruby. macOS Homebrew currently ships Ruby 4.x, so use `rbenv` (or
`asdf`) to pin 3.3 for this folder:

```sh
brew install rbenv
rbenv install 3.3.4
cd docs
rbenv local 3.3.4         # writes docs/.ruby-version (already in repo)
bundle install            # installs into vendor/bundle (gitignored)
```

Then, from the repo root:

```sh
make docs-serve           # bundle exec jekyll serve --livereload
```

Open <http://127.0.0.1:4000/>. NL lives at <http://127.0.0.1:4000/nl/>.

If `bundle install` complains about a Ruby version mismatch, your shell
isn't picking up the rbenv shim. Add `eval "$(rbenv init - zsh)"` to
`~/.zshrc` and reopen the terminal.

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
