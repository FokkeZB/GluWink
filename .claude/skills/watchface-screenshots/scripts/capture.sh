#!/usr/bin/env bash
# Capture `06_watchFace.png` from the booted watchOS Simulator after the
# owner has manually set up the face with GluWink complications (see
# prepare.sh). Validates the PNG is 416×496 (APP_WATCH_SERIES_10 / 46mm
# bucket — fastlane `deliver` routes device tier purely by pixel
# dimensions, so the wrong case size will be rejected at upload time).
#
# Writes the PNG to BOTH:
#   iOS/fastlane/screenshots/<locale>/06_watchFace.png  (App Store deck)
#   docs/assets/screenshots/<locale>/06_watchFace.png   (marketing site)
# so docs/scripts/sync-screenshots.sh (which skips 06_watchFace on purpose)
# doesn't have to play catch-up.
#
# Usage:
#   capture.sh --locale en-US
#   capture.sh --locale nl-NL --watch-device 'Apple Watch Series 10 (46mm)'

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
DEFAULT_WATCH_DEVICE="Apple Watch Series 11 (46mm)"
EXPECTED_W=416
EXPECTED_H=496

locale=""
watch_device="$DEFAULT_WATCH_DEVICE"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --locale) locale="$2"; shift 2 ;;
        --watch-device) watch_device="$2"; shift 2 ;;
        -h|--help) sed -n '3,20p' "$0"; exit 0 ;;
        *) echo "Unknown arg: $1" >&2; exit 64 ;;
    esac
done

if [[ -z "$locale" ]]; then
    echo "ERROR: --locale is required (e.g. en-US, nl-NL)" >&2
    exit 64
fi

if [[ ! -f "$REPO_ROOT/AppStore/$locale.md" ]]; then
    echo "ERROR: AppStore/$locale.md does not exist — unknown locale." >&2
    exit 64
fi

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
    echo "       Run \`make watchface-prepare LOCALE=$locale\` first, or pass --watch-device." >&2
    exit 1
fi

# Confirm the sim is actually booted — otherwise `simctl io` returns a
# pitch-black frame with no error exit and we'd happily clobber the
# existing PNG with garbage.
state="$(xcrun simctl list devices -j \
    | /usr/bin/python3 -c '
import json, sys
data = json.load(sys.stdin)
udid = sys.argv[1]
for devs in data["devices"].values():
    for d in devs:
        if d.get("udid") == udid:
            print(d.get("state", "Unknown"))
            sys.exit(0)
' "$watch_udid")"

if [[ "$state" != "Booted" ]]; then
    echo "ERROR: Sim $watch_device is $state, not Booted." >&2
    echo "       Run \`make watchface-prepare LOCALE=$locale\` first." >&2
    exit 1
fi

fastlane_dir="$REPO_ROOT/iOS/fastlane/screenshots/$locale"
docs_dir="$REPO_ROOT/docs/assets/screenshots/$locale"
mkdir -p "$fastlane_dir" "$docs_dir"

out="$fastlane_dir/06_watchFace.png"

echo "==> Capturing from $watch_device ($watch_udid)"
xcrun simctl io "$watch_udid" screenshot "$out" >/dev/null 2>&1

# Validate dimensions. `sips` is always available on macOS and doesn't
# need a venv dance. Anything other than 416×496 will be rejected by
# fastlane deliver at upload time, so fail fast here with a clearer
# message than deliver's "Invalid image dimensions".
dims="$(sips -g pixelWidth -g pixelHeight "$out" 2>/dev/null \
    | awk '/pixelWidth/ {w=$2} /pixelHeight/ {h=$2} END {printf "%dx%d", w, h}')"

if [[ "$dims" != "${EXPECTED_W}x${EXPECTED_H}" ]]; then
    echo "ERROR: captured PNG is $dims, expected ${EXPECTED_W}x${EXPECTED_H}." >&2
    echo "       $watch_device is probably not a 46mm model. Use" >&2
    echo "       --watch-device 'Apple Watch Series 11 (46mm)' (or Series 10 46mm)." >&2
    rm -f "$out"
    exit 1
fi

cp "$out" "$docs_dir/06_watchFace.png"

echo
echo "  $locale  ->  iOS/fastlane/screenshots/$locale/06_watchFace.png"
echo "  $locale  ->  docs/assets/screenshots/$locale/06_watchFace.png"
echo
echo "Dimensions OK ($dims). Review the PNG before committing — open in Finder,"
echo "read it in your agent client, or run: open \"$out\""
