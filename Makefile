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

.PHONY: appstore-bootstrap appstore-sync appstore-push appstore-pull

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
