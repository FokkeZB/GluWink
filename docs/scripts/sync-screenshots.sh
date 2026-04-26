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
# with docs/_includes/hero-carousel.html. The first three tell the green /
# orange / red traffic-light story — the whole point of the app. Widgets +
# settings back it up with "same status everywhere" and "tune it to your
# setup". 07_watchApp is the auto-captured watchOS scene; it lives next
# to the iPhone PNGs in the fastlane locale folder because `fastlane
# deliver` buckets screenshots by pixel dimensions, not path (see
# iOS/fastlane/Deliverfile + QUIRKS.md → "Fastlane deliver ignores
# device-size subfolders"). setupChecklist is App-Store-only (it's more
# of a funnel shot than a marketing hero), so it isn't in the site.
#
# 06_watchFace.png — watch face with complications in context — is NOT
# synced. Apple exposes no API to render a full watch face programmatically
# (ClockKit's preview surfaces only the complication tile), so the owner
# captures that one on device and commits it directly to
# docs/assets/screenshots/<locale>/06_watchFace.png and
# iOS/fastlane/screenshots/<locale>/06_watchFace.png. This script leaves
# both copies alone, and `--check` excludes the filename from its diff so
# a manually-curated face shot doesn't fail CI.
SCENES=(01_greenShield 02_orangeShield 03_redShield 04_widgets 05_settings 07_watchApp)
LOCALES=(en-US nl-NL)
# Files that live in docs/assets/screenshots/<locale>/ but are NOT synced
# from fastlane (owner-managed). Kept in a single list so --check can
# exclude them from `diff -r` with one flag each.
MANUAL_FILES=(06_watchFace.png)

mode="copy"
if [[ "${1:-}" == "--check" ]]; then mode="check"; fi

if [[ ! -d "$SRC" ]]; then
  echo "ERROR: Source deck not found at $SRC" >&2
  echo "       Run 'make appstore-screenshots' first." >&2
  exit 1
fi

copy_one() {
  local locale="$1" scene="$2" target_root="$3"
  local src_file="$SRC/$locale/$scene.png"
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

# Build the `-x <pattern>` exclude list for `diff -r` from MANUAL_FILES so
# owner-managed files (e.g. 06_watchFace.png) don't trip the check.
diff_excludes=()
for f in "${MANUAL_FILES[@]}"; do
  diff_excludes+=(-x "$f")
done

DIFF_OUT="$(diff -r "${diff_excludes[@]}" "$DST" "$TMP" 2>&1 || true)"
if [[ -n "$DIFF_OUT" ]]; then
  echo "ERROR: docs/assets/screenshots/ is out of date relative to" >&2
  echo "       iOS/fastlane/screenshots/. Re-run 'make appstore-screenshots'" >&2
  echo "       (or 'bash docs/scripts/sync-screenshots.sh') and commit the diff." >&2
  echo "" >&2
  echo "$DIFF_OUT" >&2
  exit 1
fi
echo "OK: docs/assets/screenshots/ matches the App Store deck."
