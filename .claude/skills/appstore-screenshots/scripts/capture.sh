#!/usr/bin/env bash
# Capture App Store screenshots from the iOS Simulator using the in-app
# `ScreenshotHarness` (see iOS/App/ScreenshotHarness.swift).
#
# Builds once, boots the right simulator, then loops over every
# (locale, scene) pair the user requested and writes PNGs into
# `iOS/fastlane/screenshots/<locale>/NN_<scene>.png`. No device-size
# subfolder — fastlane deliver's loader does a flat glob per locale and
# would silently ignore a subdir (see QUIRKS.md → "Fastlane deliver
# ignores device-size subfolders" and issue #95).
#
# Designed to be invoked by an agent following the appstore-screenshots
# skill, but safe to run by hand.
#
# Usage:
#   capture.sh                       # all locales × all iPhone scenes
#   capture.sh --scene redShield     # one scene, every locale
#   capture.sh --locale en-US        # one locale, every scene
#   capture.sh --scene redShield --locale en-US
#   capture.sh --no-build            # skip rebuild (faster iteration)
#   capture.sh --no-captions         # skip the marketing caption banner
#   capture.sh --device 'iPhone 17 Pro Max'
#
# Captions are pulled from AppStore/<locale>.md → "Screenshot captions" →
# "iPhone" table and baked into each screenshot by CaptionBanner.swift.
# The table row number (1..6) is matched against the scene's numeric
# prefix (01..06), so keep them aligned when adding new scenes.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
DERIVED_DATA="/tmp/glucoach-screenshots-dd"
BUNDLE_ID="nl.fokkezb.GluWink"
DEFAULT_DEVICE="iPhone 17 Pro Max"

# Scene order matches AppStore/README.md → Screenshots. The numeric prefix
# both orders the files for human review and matches the order the App Store
# Connect listing shows them. The first three scenes tell the traffic-light
# story (green → orange → red / critical) so reviewers scrolling the deck
# top-to-bottom get the three-way status model before anything else.
# Scene 06 (Apple Watch) isn't yet automated — it needs the Watch simulator
# path.
declare -a IPHONE_SCENES=(
    "01:greenShield"
    "02:orangeShield"
    "03:redShield"
    "04:widgets"
    "05:settings"
    "07:setupChecklist"
)

scene=""
locale=""
device="$DEFAULT_DEVICE"
do_build=1
captions=1
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
        --no-build) do_build=0; shift ;;
        --no-captions) captions=0; shift ;;
        -h|--help)
            sed -n '3,24p' "$0"
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

if [[ -n "$scene" ]]; then
    matched=()
    for entry in "${IPHONE_SCENES[@]}"; do
        IFS=':' read -r num name <<< "$entry"
        if [[ "$name" == "$scene" ]]; then
            matched+=("$entry")
        fi
    done
    if [[ ${#matched[@]} -eq 0 ]]; then
        echo "Unknown scene: $scene" >&2
        echo "Known scenes: $(printf '%s ' "${IPHONE_SCENES[@]##*:}")" >&2
        exit 64
    fi
    scenes=("${matched[@]}")
else
    scenes=("${IPHONE_SCENES[@]}")
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

echo "==> Booting simulator: $device"
xcrun simctl boot "$device" 2>/dev/null || true
xcrun simctl bootstatus "$device" -b >/dev/null

if [[ "$do_build" -eq 1 ]]; then
    echo "==> Building (this is the slow step)"
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
    echo "ERROR: build product not found at $APP_PATH" >&2
    echo "Run without --no-build at least once." >&2
    exit 1
fi

echo "==> Installing $APP_PATH"
xcrun simctl install booted "$APP_PATH"

echo "==> Locking status bar to 9:41, full bars, full battery"
xcrun simctl status_bar booted override \
    --time '9:41' \
    --batteryState charged \
    --batteryLevel 100 \
    --cellularBars 4 \
    --wifiBars 3 \
    --dataNetwork wifi

# Capture loop ---------------------------------------------------------------
for loc in "${locales[@]}"; do
    lang="$(language_code_for_locale "$loc")"
    posix="$(posix_locale_for_locale "$loc")"
    out_dir="$REPO_ROOT/iOS/fastlane/screenshots/$loc"
    mkdir -p "$out_dir"

    for entry in "${scenes[@]}"; do
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
        echo "  $loc  $name  ->  ${out#$REPO_ROOT/}"
    done
done

xcrun simctl terminate booted "$BUNDLE_ID" 2>/dev/null || true

echo
echo "Done. Review the PNGs under iOS/fastlane/screenshots/ before pushing."
echo "Tip: read each file in your agent client to eyeball them, or open them in Finder."
