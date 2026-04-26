#!/usr/bin/env bash
# Capture App Store screenshots from the iOS and watchOS Simulators using
# the in-app `ScreenshotHarness` (iPhone — iOS/App/ScreenshotHarness.swift)
# and `WatchScreenshotHarness` (Apple Watch — iOS/WatchApp/WatchScreenshotHarness.swift).
#
# Builds once, boots the right simulators, then loops over every
# (locale, scene) pair the user requested and writes PNGs into
# `iOS/fastlane/screenshots/<locale>/NN_<scene>.png`. Both iPhone and
# Apple Watch screenshots land flat in the same locale folder — fastlane
# `deliver` detects the device tier from PNG pixel dimensions, not the
# folder path (1320×2868 → APP_IPHONE_67, 396×484 → APP_WATCH_SERIES_7
# which is App Store Connect's 45mm bucket for Series 7/8/9/10/11 45mm).
# Any subdir under the locale folder would fail loader validation, see
# `deliver/lib/deliver/loader.rb` + QUIRKS.md → "Fastlane deliver ignores
# device-size subfolders" + issue #95.
#
# The Apple Watch deck also includes a manually-captured watch-face-with-
# complications PNG (`06_watchFace.png`) that Apple's simulator + ClockKit
# preview APIs can't render programmatically — see SKILL.md → "Manual
# shots". The owner captures that one on device; this script leaves it
# alone.
#
# Designed to be invoked by an agent following the appstore-screenshots
# skill, but safe to run by hand.
#
# Usage:
#   capture.sh                       # all locales × all scenes (iPhone + Watch)
#   capture.sh --scene redShield     # one scene, every locale
#   capture.sh --scene watchApp      # watchOS scene, every locale
#   capture.sh --locale en-US        # one locale, every scene
#   capture.sh --scene redShield --locale en-US
#   capture.sh --no-build            # skip rebuild (faster iteration)
#   capture.sh --no-captions         # skip the marketing caption banner (iPhone only)
#   capture.sh --device 'iPhone 17 Pro Max'
#   capture.sh --watch-device 'Apple Watch Series 10 (45mm)'
#   capture.sh --skip-watch          # iPhone only (e.g. Watch sim unavailable)
#
# Captions are pulled from AppStore/<locale>.md → "Screenshot captions" →
# "iPhone" table and baked into each iPhone screenshot by CaptionBanner.swift.
# Watch screenshots never carry a caption — the screen is too small and
# the App Store Connect listing doesn't use per-shot caption fields.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
DERIVED_DATA="/tmp/glucoach-screenshots-dd"
BUNDLE_ID="nl.fokkezb.GluWink"
WATCH_BUNDLE_ID="nl.fokkezb.GluWink.watchkitapp"
DEFAULT_DEVICE="iPhone 17 Pro Max"
# Default Watch sim target. Must be a 45mm Series 10/11 (396×484 screen),
# which fastlane maps to the App Store Connect "Apple Watch Series 7" /
# 45mm bucket. The name below is the canonical `xcrun simctl list
# devicetypes` identifier at the time of writing; override with
# --watch-device if the simctl catalogue has rotated.
DEFAULT_WATCH_DEVICE="Apple Watch Series 10 (45mm)"

# Scene order matches AppStore/README.md → Screenshots. The numeric prefix
# orders files for human review AND is the App Store Connect deck order
# (ASC sorts by filename within each device tier). The first three scenes
# tell the traffic-light story (green → orange → red / critical).
#
# iPhone bucket: 01–05 + 07_setupChecklist. 06 is reserved for the Apple
# Watch face shot (different device tier — no filename collision).
declare -a IPHONE_SCENES=(
    "01:greenShield"
    "02:orangeShield"
    "03:redShield"
    "04:widgets"
    "05:settings"
    "07:setupChecklist"
)

# Apple Watch bucket. 06_watchFace.png (watch face with complications in
# context) is owner-supplied and committed directly — Apple exposes no API
# to render a full watch face programmatically, only the complication
# tile. 07_watchApp.png is the WatchApp UI, auto-captured via the
# WatchScreenshotHarness on the watchOS simulator.
declare -a WATCH_SCENES=(
    "07:watchApp"
)

scene=""
locale=""
device="$DEFAULT_DEVICE"
watch_device="$DEFAULT_WATCH_DEVICE"
do_build=1
captions=1
skip_watch=0
# Fail fast on captions longer than this. 80 chars fits comfortably on three
# lines at the heavy rounded 30pt used by CaptionBanner on a 6.9" screen;
# anything longer starts shrinking below the minimumScaleFactor and looks
# cramped next to the shield.
CAPTION_HARD_LIMIT=80
# Softer ceiling: above this, print a warning but still render. Gives
# translators a headroom heads-up before hitting the hard stop.
CAPTION_WARN_LIMIT=65

while [[ $# -gt 0 ]]; do
    case "$1" in
        --scene) scene="$2"; shift 2 ;;
        --locale) locale="$2"; shift 2 ;;
        --device) device="$2"; shift 2 ;;
        --watch-device) watch_device="$2"; shift 2 ;;
        --no-build) do_build=0; shift ;;
        --no-captions) captions=0; shift ;;
        --skip-watch) skip_watch=1; shift ;;
        -h|--help)
            sed -n '3,45p' "$0"
            exit 0
            ;;
        *) echo "Unknown arg: $1" >&2; exit 64 ;;
    esac
done

# Discover locales from AppStore/<locale>.md (the canonical list — every
# locale present here should get a screenshot pass).
discover_locales() {
    local files=("$REPO_ROOT"/AppStore/*.md)
    for f in "${files[@]}"; do
        local base="${f##*/}"
        base="${base%.md}"
        [[ "$base" == "README" ]] && continue
        echo "$base"
    done
}

if [[ -n "$locale" ]]; then
    locales=("$locale")
else
    # bash 3.2 (macOS default) has no `mapfile`, hence the manual loop.
    locales=()
    while IFS= read -r line; do
        locales+=("$line")
    done < <(discover_locales)
fi

# Resolve the scenes to run — one list per device tier. `--scene <name>`
# picks from whichever tier contains the scene; without it, both tiers
# run in full.
iphone_scenes=()
watch_scenes=()
if [[ -n "$scene" ]]; then
    for entry in "${IPHONE_SCENES[@]}"; do
        IFS=':' read -r _num name <<< "$entry"
        [[ "$name" == "$scene" ]] && iphone_scenes+=("$entry")
    done
    for entry in "${WATCH_SCENES[@]}"; do
        IFS=':' read -r _num name <<< "$entry"
        [[ "$name" == "$scene" ]] && watch_scenes+=("$entry")
    done
    if [[ ${#iphone_scenes[@]} -eq 0 && ${#watch_scenes[@]} -eq 0 ]]; then
        echo "Unknown scene: $scene" >&2
        echo "iPhone scenes: $(printf '%s ' "${IPHONE_SCENES[@]##*:}")" >&2
        echo "Watch scenes:  $(printf '%s ' "${WATCH_SCENES[@]##*:}")" >&2
        exit 64
    fi
else
    iphone_scenes=("${IPHONE_SCENES[@]}")
    watch_scenes=("${WATCH_SCENES[@]}")
fi

if [[ "$skip_watch" -eq 1 ]]; then
    watch_scenes=()
fi

# Map App Store locale code (en-US, nl-NL) to system language code (en, nl).
# Apple's locale picker uses the system codes, not the App Store ones.
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

# Pull a caption out of AppStore/<locale>.md by row number. Looks for the
# first Markdown table under the "iPhone" subheading and picks the row whose
# "#" column (digit-only, even if wrapped in " *(optional)*") matches.
#
# Keeping this in awk rather than Ruby avoids spawning a separate interpreter
# per scene × locale — 10 caption lookups per run shouldn't cost a second.
caption_for() {
    local loc="$1"
    local num="$2"
    local md="$REPO_ROOT/AppStore/$loc.md"
    [[ -f "$md" ]] || { echo ""; return; }
    local n="${num#0}"
    awk -v want="$n" '
        /^### iPhone/ { in_iphone = 1; next }
        /^### / && in_iphone { exit }
        in_iphone && /^\|[[:space:]]*[0-9]/ {
            line = $0
            sub(/^\|[[:space:]]*/, "", line)
            n = split(line, parts, /\|/)
            num_part = parts[1]
            gsub(/[^0-9]/, "", num_part)
            if (num_part == want && n >= 2) {
                cap = parts[2]
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", cap)
                print cap
                exit
            }
        }
    ' "$md"
}

# ---------------------------------------------------------------------------
# iPhone capture path
# ---------------------------------------------------------------------------

if [[ ${#iphone_scenes[@]} -gt 0 ]]; then
    echo "==> iPhone: booting simulator: $device"
    xcrun simctl boot "$device" 2>/dev/null || true
    xcrun simctl bootstatus "$device" -b >/dev/null

    if [[ "$do_build" -eq 1 ]]; then
        echo "==> iPhone: building (this is the slow step)"
        xcodebuild \
            -project "$REPO_ROOT/iOS/App.xcodeproj" \
            -scheme App \
            -configuration Debug \
            -destination "platform=iOS Simulator,name=$device" \
            -derivedDataPath "$DERIVED_DATA" \
            -quiet \
            build
    fi

    APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/App.app"
    if [[ ! -d "$APP_PATH" ]]; then
        echo "ERROR: iPhone build product not found at $APP_PATH" >&2
        echo "Run without --no-build at least once." >&2
        exit 1
    fi

    echo "==> iPhone: installing $APP_PATH"
    xcrun simctl install booted "$APP_PATH"

    echo "==> iPhone: locking status bar to 9:41, full bars, full battery"
    xcrun simctl status_bar booted override \
        --time '9:41' \
        --batteryState charged \
        --batteryLevel 100 \
        --cellularBars 4 \
        --wifiBars 3 \
        --dataNetwork wifi

    for loc in "${locales[@]}"; do
        lang="$(language_code_for_locale "$loc")"
        posix="$(posix_locale_for_locale "$loc")"
        out_dir="$REPO_ROOT/iOS/fastlane/screenshots/$loc"
        mkdir -p "$out_dir"

        for entry in "${iphone_scenes[@]}"; do
            IFS=':' read -r num name <<< "$entry"
            out="$out_dir/${num}_${name}.png"

            caption=""
            if [[ "$captions" -eq 1 ]]; then
                caption="$(caption_for "$loc" "$num")"
                if [[ -z "$caption" ]]; then
                    echo "ERROR: no caption row $num in AppStore/$loc.md (iPhone table)" >&2
                    exit 65
                fi
                cap_len=${#caption}
                if (( cap_len > CAPTION_HARD_LIMIT )); then
                    echo "ERROR: caption $loc #$num is $cap_len chars (> $CAPTION_HARD_LIMIT): $caption" >&2
                    exit 65
                elif (( cap_len > CAPTION_WARN_LIMIT )); then
                    echo "WARN:  caption $loc #$num is $cap_len chars (> $CAPTION_WARN_LIMIT): $caption" >&2
                fi
            fi

            xcrun simctl terminate booted "$BUNDLE_ID" 2>/dev/null || true
            if [[ -n "$caption" ]]; then
                xcrun simctl launch booted "$BUNDLE_ID" \
                    --args \
                    -UITest_Scene "$name" \
                    -UITest_Caption "$caption" \
                    -AppleLanguages "($lang)" \
                    -AppleLocale "$posix" \
                    >/dev/null
            else
                xcrun simctl launch booted "$BUNDLE_ID" \
                    --args \
                    -UITest_Scene "$name" \
                    -AppleLanguages "($lang)" \
                    -AppleLocale "$posix" \
                    >/dev/null
            fi

            # Two seconds is enough for a SwiftUI render on a warm sim. Bump
            # if a scene starts looking partially drawn (e.g. an asynchronous
            # data-source row landing late).
            sleep 2

            xcrun simctl io booted screenshot "$out" >/dev/null 2>&1
            echo "  iPhone  $loc  $name  ->  ${out#$REPO_ROOT/}"
        done
    done

    xcrun simctl terminate booted "$BUNDLE_ID" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Apple Watch capture path
# ---------------------------------------------------------------------------

if [[ ${#watch_scenes[@]} -gt 0 ]]; then
    # Resolve the Watch sim UDID by name. `simctl boot <name>` works when
    # the name is unique, but later `simctl io <name> screenshot` can be
    # flaky if multiple runtimes expose the same device name — the UDID is
    # unambiguous and survives sim catalogue churn.
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
        echo "       or pass --watch-device '<name>' / --skip-watch to bypass." >&2
        exit 1
    fi

    echo "==> Watch: booting simulator: $watch_device ($watch_udid)"
    xcrun simctl boot "$watch_udid" 2>/dev/null || true
    xcrun simctl bootstatus "$watch_udid" -b >/dev/null

    if [[ "$do_build" -eq 1 ]]; then
        echo "==> Watch: building (watchOS Simulator)"
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
        echo "Run without --no-build at least once." >&2
        exit 1
    fi

    echo "==> Watch: installing $WATCH_APP_PATH"
    xcrun simctl install "$watch_udid" "$WATCH_APP_PATH"

    for loc in "${locales[@]}"; do
        lang="$(language_code_for_locale "$loc")"
        posix="$(posix_locale_for_locale "$loc")"
        out_dir="$REPO_ROOT/iOS/fastlane/screenshots/$loc"
        mkdir -p "$out_dir"

        for entry in "${watch_scenes[@]}"; do
            IFS=':' read -r num name <<< "$entry"
            out="$out_dir/${num}_${name}.png"

            xcrun simctl terminate "$watch_udid" "$WATCH_BUNDLE_ID" 2>/dev/null || true
            xcrun simctl launch "$watch_udid" "$WATCH_BUNDLE_ID" \
                --args \
                -UITest_Scene "$name" \
                -AppleLanguages "($lang)" \
                -AppleLocale "$posix" \
                >/dev/null

            # watchOS SwiftUI is a little slower to settle than iOS — the
            # first-run container copy + the timer publisher kicking in
            # want a touch more headroom than the iPhone's 2s.
            sleep 3

            xcrun simctl io "$watch_udid" screenshot "$out" >/dev/null 2>&1
            echo "  Watch   $loc  $name  ->  ${out#$REPO_ROOT/}"
        done
    done

    xcrun simctl terminate "$watch_udid" "$WATCH_BUNDLE_ID" 2>/dev/null || true
fi

echo
echo "Done. Review the PNGs under iOS/fastlane/screenshots/ before pushing."
echo "Tip: read each file in your agent client to eyeball them, or open them in Finder."
