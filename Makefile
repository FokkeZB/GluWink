XCODE_PROJECT := iOS/App.xcodeproj
SCHEME := App
# `devicectl list devices` reports state as `available (paired)` / `unavailable`
# on Xcode 16+; the older `connected` keyword is gone. Filter on `iPhone` AND
# `available` so we ignore paired Apple Watches and offline iPhones, then pick
# the first UUID-shaped field on the matching line.
DEVICE_ID = $(shell xcrun devicectl list devices 2>/dev/null | awk '/iPhone/ && /available/ {for(i=1;i<=NF;i++) if($$i ~ /^[0-9A-F].*-/) {print $$i; exit}}')
DERIVED_DATA := $(HOME)/Library/Developer/Xcode/DerivedData
# Lazy assignment (`=`) so APP_PATH is re-evaluated at recipe time — this matters
# for `make deploy: build install`, otherwise APP_PATH is resolved before `build`
# runs and points at a stale artifact. Glob is scoped to `*-iphoneos` so we
# never accidentally pick a simulator build (devicectl rejects those with a
# confusing code-signature error).
APP_PATH = $(shell ls -dt $(DERIVED_DATA)/App-*/Build/Products/*-iphoneos/App.app 2>/dev/null | head -1)

VENV_DIR := $(HOME)/.cache/ios-screenshot-venv
VENV_PYTHON := $(VENV_DIR)/bin/python3
PMD3 := $(VENV_DIR)/bin/pymobiledevice3

# --- Agent config ---

.PHONY: cursor-perms-sync

## Merge .cursor/permissions.example.json into ~/.cursor/permissions.json.
## Cursor's terminal allowlist is per-user only — this keeps your personal
## file in sync with the curated set we ship in the repo. Idempotent and
## additive (entries already in your file are preserved). Re-run after
## pulling changes that touch .cursor/permissions.example.json.
## See AGENTS.md → 'Agent terminal allowlist' for the rationale.
cursor-perms-sync:
	@set -e; \
	mkdir -p $(HOME)/.cursor; \
	if [ -f $(HOME)/.cursor/permissions.json ]; then \
		jq -s '(.[0] // {}) as $$cur | (.[1] // {}) as $$new | $$cur * $$new | .terminalAllowlist = ((($$cur.terminalAllowlist // []) + ($$new.terminalAllowlist // [])) | unique)' \
			$(HOME)/.cursor/permissions.json .cursor/permissions.example.json \
			> $(HOME)/.cursor/permissions.json.tmp; \
		mv $(HOME)/.cursor/permissions.json.tmp $(HOME)/.cursor/permissions.json; \
		echo "Merged .cursor/permissions.example.json into $(HOME)/.cursor/permissions.json."; \
	else \
		cp .cursor/permissions.example.json $(HOME)/.cursor/permissions.json; \
		echo "Created $(HOME)/.cursor/permissions.json from .cursor/permissions.example.json."; \
	fi; \
	echo "Cursor will re-read the file on save — no restart needed."

# --- Build & deploy ---

.PHONY: build install deploy tunneld screenshot venv-clean

## Build debug configuration (fallback — prefer Xcode MCP BuildProject).
## Runs `clean build` rather than a bare `build` so we can never inherit a
## stale, unsigned, simulator-arch bundle from an earlier verification run
## that wrote into the shared DerivedData entry (see QUIRKS.md → "Shared
## DerivedData can produce unsigned device builds"). Costs ~30s vs a ~5s
## no-op incremental — acceptable because this is the fallback path; the
## inner loop is the Xcode MCP BuildProject tool.
build:
	xcodebuild -project $(XCODE_PROJECT) -scheme $(SCHEME) \
		-destination 'generic/platform=iOS' \
		-configuration Debug clean build

## Install the last build on the connected iPhone
install:
	@if [ -z "$(DEVICE_ID)" ]; then echo "ERROR: No connected device found. Connect an iPhone via USB and unlock it." >&2; exit 1; fi
	@if [ -z "$(APP_PATH)" ]; then echo "ERROR: No build found in DerivedData. Run 'make build' or build via Xcode first." >&2; exit 1; fi
	@OUTPUT=$$(xcrun devicectl device install app --device $(DEVICE_ID) $(APP_PATH) 2>&1); \
	echo "$$OUTPUT"; \
	if echo "$$OUTPUT" | grep -q "App installed"; then \
		echo "SUCCESS: App installed on device."; \
	else \
		echo "ERROR: Install failed. See output above." >&2; exit 1; \
	fi

## Build and install (fallback — prefer BuildProject MCP + make install)
deploy: build install

# --- iOS device screenshot tooling ---

## Start the USB tunnel daemon (required once per session, needs sudo)
tunneld: $(PMD3)
	sudo $(VENV_PYTHON) -m pymobiledevice3 remote tunneld

## Take a screenshot from the connected iPhone
screenshot: $(PMD3)
	@bash .claude/skills/ios-screenshot/scripts/screenshot.sh /tmp/iphone_screenshot.png

## Bootstrap the isolated venv (auto-runs if needed)
$(PMD3):
	@echo "Creating isolated venv at $(VENV_DIR)..."
	@python3 -m venv $(VENV_DIR)
	@$(VENV_PYTHON) -m pip install --quiet pymobiledevice3
	@echo "Done."

## Remove the venv (to force a clean reinstall)
venv-clean:
	rm -rf $(VENV_DIR)

# --- App Store listing (fastlane deliver) ---

.PHONY: appstore-bootstrap appstore-sync appstore-push appstore-pull appstore-screenshots appstore-beta release watchface-prepare watchface-capture docs-sync-screenshots docs-bootstrap docs-serve docs-clean docs-build docs-publish-check docs-audit docs-check docs-og-images

## One-time: install fastlane into iOS/vendor/bundle (uses iOS/Gemfile)
appstore-bootstrap:
	cd iOS && $(RUN_RUBY) bundle config set --local path 'vendor/bundle' && $(RUN_RUBY) bundle install

## Regenerate iOS/fastlane/metadata/ from AppStore/<locale>.md
appstore-sync:
	cd iOS && $(RUN_RUBY) bundle exec fastlane sync_metadata

## Push App Store listing copy to App Store Connect (regenerates first).
## Requires private/asc-api-key.json — see AppStore/README.md.
appstore-push:
	cd iOS && $(RUN_RUBY) bundle exec fastlane push_metadata

## Download current App Store metadata into iOS/fastlane/metadata/ (snapshot only)
appstore-pull:
	cd iOS && $(RUN_RUBY) bundle exec fastlane pull_metadata

## Regenerate the App Store screenshot deck (every scene × every locale).
## Writes PNGs into iOS/fastlane/screenshots/<locale>/ (flat — no device-size
## subfolder; deliver's loader ignores subdirs, see QUIRKS.md), then copies
## the curated subset into docs/assets/screenshots/ so the marketing site
## stays in lock-step. CI fails (.github/workflows/screenshots-sync-
## check.yml) if the two drift.
appstore-screenshots: _capture-screenshots docs-sync-screenshots docs-og-images

_capture-screenshots:
	bash .claude/skills/appstore-screenshots/scripts/capture.sh

## Copy curated screenshots into docs/assets/screenshots/ (see docs/scripts).
docs-sync-screenshots:
	bash docs/scripts/sync-screenshots.sh

## Prepare the watchOS Simulator for a manual 06_watchFace.png capture.
## Boots the 46mm Watch sim, sets its system language to LOCALE (so the
## watch face's weekday/date localise), builds and installs WatchApp so
## the complication picker lists GluWink, and brings Simulator.app to
## the front. The owner then manually adds GluWink complications to the
## face and runs `make watchface-capture LOCALE=...`.
## See .claude/skills/watchface-screenshots/SKILL.md for the full flow.
## Usage: make watchface-prepare LOCALE=en-US [WATCH_DEVICE='Apple Watch Series 10 (46mm)'] [NO_BUILD=1]
LOCALE ?=
WATCH_DEVICE ?= Apple Watch Series 11 (46mm)
NO_BUILD ?=

watchface-prepare:
	@if [ -z "$(LOCALE)" ]; then echo "ERROR: LOCALE is required (e.g. make watchface-prepare LOCALE=en-US)" >&2; exit 64; fi
	bash .claude/skills/watchface-screenshots/scripts/prepare.sh \
		--locale "$(LOCALE)" \
		--watch-device "$(WATCH_DEVICE)" \
		$(if $(NO_BUILD),--no-build,)

## Capture 06_watchFace.png from the booted watchOS Simulator and write
## it to both iOS/fastlane/screenshots/<locale>/ (App Store deck) and
## docs/assets/screenshots/<locale>/ (marketing site). Validates the
## PNG is 416x496 (APP_WATCH_SERIES_10 / 46mm bucket) — anything else is
## rejected so fastlane deliver won't fail at upload time.
## Run `make watchface-prepare LOCALE=...` first.
## Usage: make watchface-capture LOCALE=en-US [WATCH_DEVICE=...]
watchface-capture:
	@if [ -z "$(LOCALE)" ]; then echo "ERROR: LOCALE is required (e.g. make watchface-capture LOCALE=en-US)" >&2; exit 64; fi
	bash .claude/skills/watchface-screenshots/scripts/capture.sh \
		--locale "$(LOCALE)" \
		--watch-device "$(WATCH_DEVICE)"

# `mise exec ruby --` resolves `bundle` / `ruby` to the Ruby pinned in
# mise.toml + docs/.ruby-version. Scoped to `ruby` so we don't trigger
# install of unrelated tools from the contributor's global mise config.
RUN_RUBY := mise exec ruby --

## One-time: install pinned tools (mise.toml) + gem deps for the
## marketing site. Requires mise (https://mise.jdx.dev/) and the
## Ruby build deps on macOS: `brew install openssl@3 readline libyaml gmp`.
## Idempotent — safe to re-run after pulling changes to docs/Gemfile.
docs-bootstrap:
	@command -v mise >/dev/null || { echo "ERROR: mise not found. Install with 'brew install mise && echo \"eval \\\"\\$$(mise activate zsh)\\\"\" >> ~/.zshrc && exec zsh'." >&2; exit 1; }
	mise install ruby gh jq
	cd docs && $(RUN_RUBY) bundle config set --local path 'vendor/bundle' && $(RUN_RUBY) bundle install

## Serve the marketing site locally on http://127.0.0.1:4000/.
## Run `make docs-bootstrap` once first. Aborts early if the active Ruby
## doesn't match docs/.ruby-version (the github-pages gem can't run on
## Ruby 4.x — Liquid 4.0 still calls Object#tainted?).
docs-serve:
	@cd docs && $(RUN_RUBY) ruby -e 'exit RUBY_VERSION.start_with?("3.3.") ? 0 : 1' || { echo "ERROR: docs/ requires Ruby 3.3.x (see docs/.ruby-version). Run 'make docs-bootstrap' first." >&2; exit 1; }
	cd docs && $(RUN_RUBY) bundle exec jekyll serve --livereload

## Wipe Jekyll's build output and caches under docs/. Safe to run anytime;
## the next `docs-build` / `docs-serve` will regenerate everything.
docs-clean:
	rm -rf docs/_site docs/.jekyll-cache docs/.sass-cache

## Build the marketing site exactly as GitHub Pages will, into docs/_site/.
## Sets JEKYLL_ENV=production so any production-only conditionals fire.
## Always starts from a clean tree so cached or stale output can't mask a
## real publish-time failure.
docs-build: docs-clean
	@cd docs && $(RUN_RUBY) ruby -e 'exit RUBY_VERSION.start_with?("3.3.") ? 0 : 1' || { echo "ERROR: docs/ requires Ruby 3.3.x (see docs/.ruby-version). Run 'make docs-bootstrap' first." >&2; exit 1; }
	cd docs && JEKYLL_ENV=production $(RUN_RUBY) bundle exec jekyll build

## Final pre-merge sanity check: clean production build, then serve the
## static docs/_site/ from a vanilla HTTP server on http://127.0.0.1:4001/.
## `docs-serve` runs Jekyll's dev server with live-reload, which can mask
## issues (missing assets, wrong relative_url, Liquid-only-in-includes
## breakage) that only surface in the static output GitHub Pages publishes.
## Uses port 4001 so it can run alongside `docs-serve` (which owns 4000).
docs-publish-check: docs-build
	@echo "Serving production build of docs/_site/ at http://127.0.0.1:4001/ — Ctrl-C to stop."
	cd docs/_site && python3 -m http.server 4001 --bind 127.0.0.1

## Run a Lighthouse audit (perf / a11y / best-practices / seo) against a
## production-mirror build of the marketing site, on both `/` and `/nl/`,
## and print a compact summary + the audits that need attention.
##
## Builds the site fresh, boots its own http server on :4001 (or reuses
## one if you already have `docs-publish-check` running), and writes raw
## JSON reports to /tmp/glucwink-lh/ for follow-up drilldown. Cache and
## document-latency insights are filtered out — they're artifacts of the
## local python http server, not production issues.
##
## Pairs with .claude/skills/site-audit/SKILL.md: just say "audit the
## site" and the agent will run this, file an issue with what to fix,
## and offer to fix it.
docs-audit:
	bash docs/scripts/lighthouse-audit.sh

## Run the same gates GitHub Actions runs on every docs-touching PR
## (.github/workflows/docs-check.yml). Three layers, each catching a
## distinct class of regression — keep this target and the workflow
## in lock-step so "passes locally" means "passes CI":
##
##   1. Production Jekyll build (Liquid errors, missing _data refs,
##      plugin loading failures — anything that crashes the build).
##   2. htmlproofer over docs/_site/ — broken internal links, missing
##      images (including og:image), missing alt attributes, malformed
##      HTML. External links are skipped (--disable-external) so the
##      check stays unflaky; periodic external-link audits belong in
##      a cron, not a per-PR gate.
##   3. docs/scripts/site-check.sh — project-specific smoke greps that
##      defend the canonical/OG/sitemap/robots invariants we don't
##      want to regress. See the script's header for the full list.
##
## See #62 for the design and staged rollout.
docs-check: docs-build
	cd docs && $(RUN_RUBY) bundle exec htmlproofer _site \
		--disable-external --no-enforce-https --no-ignore-empty-alt
	bash docs/scripts/site-check.sh

## Regenerate docs/assets/og-{en,nl}.png — the per-locale Open Graph cards
## referenced by data.meta.og_image. Idempotent. Requires Python 3 with
## Pillow (already on the standard dev-machine setup). Run after editing
## the headline copy, the brand wash colour, or the hero screenshot.
docs-og-images:
	python3 docs/scripts/generate-og-images.py

## Build a Release archive and upload it to TestFlight.
## Auto-bumps the build number from the latest TestFlight build and uses
## Xcode-managed signing. Requires private/asc-api-key.json and being
## signed into Xcode with the development team.
## See AppStore/README.md → "Releasing a TestFlight build".
appstore-beta:
	cd iOS && $(RUN_RUBY) bundle exec fastlane beta

## Bump version, push metadata, upload binary to App Store Connect, and
## optionally submit for review. VERSION is required. Pass SUBMIT=1 to
## submit for review; omit it to stage everything in ASC first (dry run).
## Requires private/asc-api-key.json and being signed into Xcode with
## the development team. See AppStore/README.md → "Shipping a release".
## Usage: make release VERSION=1.2.0 [SUBMIT=1]
release:
	@if [ -z "$(VERSION)" ]; then echo "ERROR: VERSION is required (e.g. make release VERSION=1.2.0)" >&2; exit 1; fi
	cd iOS && $(RUN_RUBY) bundle exec fastlane release version:$(VERSION) submit:$(if $(SUBMIT),true,false)
