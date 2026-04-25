#!/usr/bin/env bash
# Sync curated screenshots from iOS/fastlane/screenshots/ into
# docs/assets/screenshots/. The marketing site references PNGs by relative
# URL — Jekyll on GitHub Pages drops symlinks in safe mode, so a copy is
# the only reliable option.
#
# Usage:
#   bash docs/scripts/sync-screenshots.sh           # copy / overwrite
#   bash docs/scripts/sync-screenshots.sh --check   # exit non-zero if dirty
#
# The --check mode is what .github/workflows/screenshots-sync-check.yml runs
# on every PR: it copies into a tempdir, diffs against the committed deck,
# and fails the workflow if they differ — preventing the App Store deck and
# the marketing site from drifting silently.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="$ROOT/iOS/fastlane/screenshots"
DST="$ROOT/docs/assets/screenshots"

# Scenes the marketing site uses, in the order it shows them. Keep in sync
# with docs/_includes/hero-carousel.html. Watch (scene 6) is omitted on
# purpose — the capture pipeline doesn't yet automate Apple Watch shots.
# The first three tell the green / orange / red traffic-light story — the
# whole point of the app. Widgets + settings back it up with "same status
# everywhere" and "tune it to your setup". setupChecklist is App-Store-only
# (it's more of a funnel shot than a marketing hero), so it isn't in the
# site carousel.
SCENES=(01_greenShield 02_orangeShield 03_redShield 04_widgets 05_settings)
LOCALES=(en-US nl-NL)
SIZE="iPhone-6.9"

mode="copy"
if [[ "${1:-}" == "--check" ]]; then mode="check"; fi

if [[ ! -d "$SRC" ]]; then
  echo "ERROR: Source deck not found at $SRC" >&2
  echo "       Run 'make appstore-screenshots' first." >&2
  exit 1
fi

copy_one() {
  local locale="$1" scene="$2" target_root="$3"
  local src_file="$SRC/$locale/$SIZE/$scene.png"
  local dst_dir="$target_root/$locale"
  local dst_file="$dst_dir/$scene.png"
  if [[ ! -f "$src_file" ]]; then
    echo "ERROR: Missing $src_file (locale=$locale, scene=$scene)" >&2
    exit 1
  fi
  mkdir -p "$dst_dir"
  cp "$src_file" "$dst_file"
}

if [[ "$mode" == "copy" ]]; then
  for locale in "${LOCALES[@]}"; do
    for scene in "${SCENES[@]}"; do
      copy_one "$locale" "$scene" "$DST"
    done
  done
  echo "OK: synced ${#LOCALES[@]} locale(s) × ${#SCENES[@]} scene(s) into docs/assets/screenshots/"
  exit 0
fi

# --- check mode -------------------------------------------------------------
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
for locale in "${LOCALES[@]}"; do
  for scene in "${SCENES[@]}"; do
    copy_one "$locale" "$scene" "$TMP"
  done
done

DIFF_OUT="$(diff -r "$DST" "$TMP" 2>&1 || true)"
if [[ -n "$DIFF_OUT" ]]; then
  echo "ERROR: docs/assets/screenshots/ is out of date relative to" >&2
  echo "       iOS/fastlane/screenshots/. Re-run 'make appstore-screenshots'" >&2
  echo "       (or 'bash docs/scripts/sync-screenshots.sh') and commit the diff." >&2
  echo "" >&2
  echo "$DIFF_OUT" >&2
  exit 1
fi
echo "OK: docs/assets/screenshots/ matches the App Store deck."
