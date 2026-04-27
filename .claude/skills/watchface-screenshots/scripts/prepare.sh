#!/usr/bin/env bash
# Prepare the watchOS Simulator for a manual `06_watchFace.png` capture:
#
#   1. Boot the 46mm Apple Watch simulator (APP_WATCH_SERIES_10 bucket, 416×496 px).
#   2. Set the watch's *system* language so face strings (weekday, date,
#      calendar "nothing scheduled") localise correctly. Launch-time
#      -AppleLanguages only affects the app we launch, not the face — we
#      need `defaults write -g` on the booted sim.
#   3. Build the WatchApp for the sim and install it (so the complication
#      picker shows GluWink when the owner edits the face by hand).
#   4. Bring the Simulator window to the front and leave it on the face so
#      the owner can long-press → Edit → add GluWink complications.
#
# After this script exits, the owner manually configures the face (see the
# skill), then runs `capture.sh` to grab the PNG.
#
# Usage:
#   prepare.sh --locale en-US
#   prepare.sh --locale nl-NL --watch-device 'Apple Watch Series 10 (46mm)'
#   prepare.sh --locale en-US --no-build   # skip rebuild (iterating across locales)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
DERIVED_DATA="/tmp/glucoach-screenshots-dd"
WATCH_BUNDLE_ID="nl.fokkezb.GluWink.watchkitapp"
DEFAULT_WATCH_DEVICE="Apple Watch Series 11 (46mm)"

locale=""
watch_device="$DEFAULT_WATCH_DEVICE"
do_build=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        --locale) locale="$2"; shift 2 ;;
        --watch-device) watch_device="$2"; shift 2 ;;
        --no-build) do_build=0; shift ;;
        -h|--help) sed -n '3,23p' "$0"; exit 0 ;;
        *) echo "Unknown arg: $1" >&2; exit 64 ;;
    esac
done

if [[ -z "$locale" ]]; then
    echo "ERROR: --locale is required (e.g. en-US, nl-NL)" >&2
    exit 64
fi

if [[ ! -f "$REPO_ROOT/AppStore/$locale.md" ]]; then
    echo "ERROR: AppStore/$locale.md does not exist — unknown locale." >&2
    echo "       Locales currently defined:" >&2
    ls "$REPO_ROOT/AppStore/" | grep -E '^[a-z]{2}-[A-Z]{2}\.md$' | sed 's/\.md$//' | sed 's/^/         /' >&2
    exit 64
fi

language_code_for_locale() {
    case "$1" in
        *-*) echo "${1%%-*}" ;;
        *) echo "$1" ;;
    esac
}

posix_locale_for_locale() {
    case "$1" in
        *-*) echo "${1%-*}_${1#*-}" ;;
        *) echo "$1" ;;
    esac
}

lang="$(language_code_for_locale "$locale")"
posix="$(posix_locale_for_locale "$locale")"

# Resolve the watch sim UDID by name (same approach as capture.sh — name
# lookup alone is flaky across runtimes, UDID is unambiguous).
watch_udid="$(xcrun simctl list devices available -j \
    | /usr/bin/python3 -c '
import json, sys
data = json.load(sys.stdin)
target = sys.argv[1]
for runtime, devs in data["devices"].items():
    if "watchOS" not in runtime:
        continue
    for d in devs:
        if d.get("name") == target and d.get("isAvailable", False):
            print(d["udid"])
            sys.exit(0)
sys.exit(1)
' "$watch_device" 2>/dev/null || true)"

if [[ -z "$watch_udid" ]]; then
    echo "ERROR: Apple Watch simulator '$watch_device' not found." >&2
    echo "       Run \`xcrun simctl list devices available\` to see what's installed," >&2
    echo "       or pass --watch-device '<name>'." >&2
    exit 1
fi

echo "==> Watch sim: $watch_device ($watch_udid)"

# Scrub the host-level "simulator watch bridge" file. See
# SharedKit/SimulatorWatchBridge.swift: on Simulator this JSON file at
# /private/tmp/dev.simulator.watch-bridge.json is the primary source of
# truth for `WatchDataManager.content()` — it overrides everything the
# `WatchScreenshotHarness` writes to the App Group. It's populated by
# the iPhone sim's `WatchSessionManager` whenever the user changes
# settings in the iOS Simulator, and persists on the host filesystem
# across sim reboots *and* across sim deletions. That means a stale
# `currentGlucose` / `glucoseFetchedAt` / threshold from a long-ago
# iPhone-sim session can silently colour the complication orange (stale
# sensor, lowered high threshold, etc.) even though the harness seeded
# green values moments earlier. Delete it so the harness's App Group
# writes are the only source of truth for the capture.
echo "==> Clearing stale simulator watch bridge (/private/tmp and /tmp)"
rm -f /private/tmp/dev.simulator.watch-bridge.json /tmp/dev.simulator.watch-bridge.json

# Set the system language by writing to the sim's NSGlobalDomain. This
# is the only knob that affects the face's weekday/date/calendar strings
# (the app's -AppleLanguages launch args only touch the app's own UI).
#
# Sequencing matters:
#   (a) Sim must be Booted for `simctl spawn defaults write` to work
#       ("Process spawn via launchd failed because device is not booted").
#   (b) A running watchOS sim that was drawn in a different language
#       doesn't always re-render the face when defaults flip underneath
#       it — a shutdown + fresh boot guarantees first-boot UI picks up
#       the new locale.
# So: boot (idempotent) → write defaults → shutdown → boot again.
echo "==> Booting $watch_device to apply language defaults"
xcrun simctl boot "$watch_udid" 2>/dev/null || true
xcrun simctl bootstatus "$watch_udid" -b >/dev/null

echo "==> Setting system language to $lang ($posix) on the sim's global defaults"
xcrun simctl spawn "$watch_udid" defaults write -g AppleLanguages -array "$lang"
xcrun simctl spawn "$watch_udid" defaults write -g AppleLocale -string "$posix"

echo "==> Shutdown + cold-boot so first-boot face renders in $lang"
xcrun simctl shutdown "$watch_udid"
xcrun simctl boot "$watch_udid"
xcrun simctl bootstatus "$watch_udid" -b >/dev/null

if [[ "$do_build" -eq 1 ]]; then
    echo "==> Building WatchApp (watchOS Simulator)"
    xcodebuild \
        -project "$REPO_ROOT/iOS/App.xcodeproj" \
        -scheme WatchApp \
        -configuration Debug \
        -destination "platform=watchOS Simulator,id=$watch_udid" \
        -derivedDataPath "$DERIVED_DATA" \
        -quiet \
        build
fi

WATCH_APP_PATH="$DERIVED_DATA/Build/Products/Debug-watchsimulator/WatchApp.app"
if [[ ! -d "$WATCH_APP_PATH" ]]; then
    echo "ERROR: Watch build product not found at $WATCH_APP_PATH" >&2
    echo "       Run without --no-build at least once." >&2
    exit 1
fi

echo "==> Installing $WATCH_APP_PATH"
xcrun simctl install "$watch_udid" "$WATCH_APP_PATH"

# chronod (the watchOS daemon that backs the face Edit → Complications
# picker) caches its list of available extensions at boot. If we install
# the WatchWidget appex into an already-booted sim, chronod won't rescan
# until the next boot — so the picker shows every other app on the sim
# but GluWink silently missing from the G's. Reboot to force the rescan.
# This costs ~15s but saves a "the complications aren't showing" dead-end
# during the manual face setup that comes next.
echo "==> Rebooting sim so chronod picks up the newly-installed complication extension"
xcrun simctl shutdown "$watch_udid"
xcrun simctl boot "$watch_udid"
xcrun simctl bootstatus "$watch_udid" -b >/dev/null

# Poke the app once so WidgetCenter reloads any live complication timelines
# — otherwise a just-installed complication shows placeholder data on first
# pick. Terminate immediately so we land back on the face, not in the app.
echo "==> Priming WatchApp (launch + terminate so complications have fresh data)"
xcrun simctl launch "$watch_udid" "$WATCH_BUNDLE_ID" \
    --args \
    -UITest_Scene watchApp \
    -AppleLanguages "($lang)" \
    -AppleLocale "$posix" \
    >/dev/null
sleep 2
xcrun simctl terminate "$watch_udid" "$WATCH_BUNDLE_ID" 2>/dev/null || true

# Bring Simulator.app to the front so the owner can interact. `open -a`
# only works with a name; the watch sim is hosted inside the same
# Simulator.app as iPhone sims.
echo "==> Bringing Simulator window forward"
open -a Simulator

cat <<EOF

==> Ready for manual face setup ($locale).

In the watchOS Simulator window:
  1. If the app is showing, press the Digital Crown (Hardware → Home, or
     Cmd-Shift-H) to return to the watch face.
  2. Long-press (click-and-hold) the face → tap Edit.
  3. Swipe left to the Complications pane.
  4. Tap a complication slot, scroll to GluWink, pick the tile you want
     (Glucose, Carbs, or Combined). Add at least one so the marketing
     point is obvious.
  5. Press the Digital Crown twice to save + return to the face.
  6. Confirm the face shows:
       - Weekday/date in the target locale ("Mon 27" for en-US,
         "ma 27" for nl-NL, etc.).
       - At least one GluWink complication, rendering real values
         (not the placeholder "--").
  7. Leave the sim on the face.

Then run:

    make watchface-capture LOCALE=$locale

which grabs the PNG, validates 416×496, and writes it to both
iOS/fastlane/screenshots/$locale/06_watchFace.png and
docs/assets/screenshots/$locale/06_watchFace.png.
EOF
