XCODE_PROJECT := iOS/App.xcodeproj
SCHEME := App
DEVICE_ID := $(shell xcrun devicectl list devices 2>/dev/null | grep -m1 'connected' | awk '{for(i=1;i<=NF;i++) if($$i ~ /^[0-9A-F].*-/) {print $$i; exit}}')
DERIVED_DATA := $(HOME)/Library/Developer/Xcode/DerivedData
APP_PATH := $(shell ls -dt $(DERIVED_DATA)/App-*/Build/Products/*/App.app 2>/dev/null | head -1)

VENV_DIR := $(HOME)/.cache/ios-screenshot-venv
VENV_PYTHON := $(VENV_DIR)/bin/python3
PMD3 := $(VENV_DIR)/bin/pymobiledevice3

# --- Build & deploy ---

.PHONY: build install deploy tunneld screenshot venv-clean

## Build debug configuration (fallback — prefer Xcode MCP BuildProject)
build:
	xcodebuild -project $(XCODE_PROJECT) -scheme $(SCHEME) \
		-destination 'generic/platform=iOS' \
		-configuration Debug build

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

.PHONY: appstore-bootstrap appstore-sync appstore-push appstore-pull appstore-screenshots appstore-beta docs-sync-screenshots docs-bootstrap docs-serve

## One-time: install fastlane into iOS/vendor/bundle (uses iOS/Gemfile)
appstore-bootstrap:
	cd iOS && bundle config set --local path 'vendor/bundle' && bundle install

## Regenerate iOS/fastlane/metadata/ from AppStore/<locale>.md
appstore-sync:
	cd iOS && bundle exec fastlane sync_metadata

## Push App Store listing copy to App Store Connect (regenerates first).
## Requires private/asc-api-key.json — see AppStore/README.md.
appstore-push:
	cd iOS && bundle exec fastlane push_metadata

## Download current App Store metadata into iOS/fastlane/metadata/ (snapshot only)
appstore-pull:
	cd iOS && bundle exec fastlane pull_metadata

## Regenerate the App Store screenshot deck (every scene × every locale).
## Writes PNGs into iOS/fastlane/screenshots/<locale>/iPhone-6.9/, then
## copies the curated subset into docs/assets/screenshots/ so the marketing
## site stays in lock-step. CI fails (.github/workflows/screenshots-sync-
## check.yml) if the two drift.
appstore-screenshots: _capture-screenshots docs-sync-screenshots

_capture-screenshots:
	bash .claude/skills/appstore-screenshots/scripts/capture.sh

## Copy curated screenshots into docs/assets/screenshots/ (see docs/scripts).
docs-sync-screenshots:
	bash docs/scripts/sync-screenshots.sh

# Prepend asdf shims so the Ruby pinned in docs/.tool-versions wins over
# any Homebrew Ruby earlier in $PATH (a common gotcha on macOS).
DOCS_PATH := $(HOME)/.asdf/shims:$(PATH)

## One-time: install Ruby per docs/.tool-versions and gem deps for the
## marketing site. Requires asdf (https://asdf-vm.com/) and the asdf-ruby
## build deps on macOS: `brew install openssl@3 readline libyaml gmp`.
## Idempotent — safe to re-run after pulling changes to docs/Gemfile.
docs-bootstrap:
	@command -v asdf >/dev/null || { echo "ERROR: asdf not found. Install with 'brew install asdf' and follow https://asdf-vm.com/guide/getting-started.html to source it in your shell." >&2; exit 1; }
	@asdf plugin list 2>/dev/null | grep -qx ruby || asdf plugin add ruby
	cd docs && asdf install
	cd docs && PATH="$(DOCS_PATH)" bundle config set --local path 'vendor/bundle' && PATH="$(DOCS_PATH)" bundle install

## Serve the marketing site locally on http://127.0.0.1:4000/.
## Run `make docs-bootstrap` once first. Aborts early if the active Ruby
## doesn't match docs/.tool-versions (the github-pages gem can't run on
## Ruby 4.x — Liquid 4.0 still calls Object#tainted?).
docs-serve:
	@cd docs && PATH="$(DOCS_PATH)" ruby -e 'exit RUBY_VERSION.start_with?("3.3.") ? 0 : 1' || { echo "ERROR: docs/ requires Ruby 3.3.x (see docs/.tool-versions). Run 'make docs-bootstrap' first." >&2; exit 1; }
	cd docs && PATH="$(DOCS_PATH)" bundle exec jekyll serve --livereload

## Build a Release archive and upload it to TestFlight.
## Auto-bumps the build number from the latest TestFlight build and uses
## Xcode-managed signing. Requires private/asc-api-key.json and being
## signed into Xcode with the development team.
## See AppStore/README.md → "Releasing a TestFlight build".
appstore-beta:
	cd iOS && bundle exec fastlane beta
