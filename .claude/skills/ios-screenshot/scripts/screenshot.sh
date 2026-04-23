#!/bin/bash
# Take a screenshot from a USB-connected iPhone.
# Only requires: python3 (ships with Xcode / macOS CLT).
# Everything else is auto-installed in an isolated venv.
#
# Usage: screenshot.sh [output_path]
#   output_path defaults to /tmp/iphone_screenshot.png
#
# Cursor users: invoke with required_permissions: ["all"]. The actual screenshot
# capture connects to the device over an IPv6 link-local address (fdXX::1 via
# the tunnel pmd3's tunneld brokers), and Cursor's default sandbox blocks that
# socket call with EPERM. The early "tunneld up?" check works in the sandbox
# (plain HTTP to 127.0.0.1), so a sandboxed run will still surface a clean
# "start tunneld" message — but the screenshot itself needs the sandbox off.
# Claude Code has no sandbox, so it Just Works there.

set -euo pipefail

OUTPUT="${1:-/tmp/iphone_screenshot.png}"
VENV_DIR="${HOME}/.cache/ios-screenshot-venv"
VENV_PYTHON="${VENV_DIR}/bin/python3"
PMD3="${VENV_DIR}/bin/pymobiledevice3"
TUNNELD_URL="http://127.0.0.1:49151/"

# --- Ensure python3 exists ---
if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 not found. Install Xcode Command Line Tools: xcode-select --install"
  exit 1
fi

# --- Bootstrap venv + pymobiledevice3 if needed ---
if [ ! -x "$PMD3" ]; then
  echo "SETUP: Creating isolated venv at ${VENV_DIR}..."
  python3 -m venv "$VENV_DIR"
  echo "SETUP: Installing pymobiledevice3 (one-time)..."
  "$VENV_PYTHON" -m pip install --quiet pymobiledevice3
  echo "SETUP: Done."
fi

# --- Check tunneld is reachable ---
# Use curl (not pgrep). pgrep is blocked in Cursor's sandbox with
# "sysmond service not found", so the old check would falsely report
# "tunneld is not running" even when it was. Hitting the HTTP endpoint
# works inside the sandbox AND tells us which devices are tunnelled
# without a separate pmd3 invocation.
TUNNELD_JSON="$(curl -s --max-time 2 "$TUNNELD_URL" 2>/dev/null || true)"
if [ -z "$TUNNELD_JSON" ]; then
  echo "ERROR: tunneld is not reachable at $TUNNELD_URL."
  echo ""
  echo "Ask the user to run this in their own terminal (needs sudo, stays running):"
  echo ""
  echo "  make tunneld"
  echo ""
  echo "(Equivalent to: sudo ${VENV_PYTHON} -m pymobiledevice3 remote tunneld)"
  echo ""
  exit 2
fi

# --- Extract the first USB-connected device's UDID from the tunneld JSON ---
# Response shape:
#   {"<UDID>":[{"tunnel-address":"fdXX::1","tunnel-port":N,"interface":"usbmux-<UDID>-USB"}],...}
# Prefer entries whose interface contains "USB"; fall back to the first key if
# none match (covers the rare Wi-Fi-only pairing case).
USB_UDID="$(printf '%s' "$TUNNELD_JSON" | "$VENV_PYTHON" -c "
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for udid, entries in d.items():
    for e in entries or []:
        if 'USB' in (e.get('interface') or ''):
            print(udid)
            sys.exit(0)
if d:
    print(next(iter(d)))
")"

if [ -z "$USB_UDID" ]; then
  echo "ERROR: tunneld is up but no devices are tunnelled."
  echo "Plug the iPhone in via USB cable, unlock it, and tap 'Trust' if prompted."
  exit 3
fi

# --- Take the screenshot ---
# Stash stderr so we can recognise the Cursor-sandbox failure mode and emit a
# clean message instead of dumping a Python traceback.
SCREENSHOT_ERR="$(mktemp -t ios-screenshot-err.XXXXXX)"
trap 'rm -f "$SCREENSHOT_ERR"' EXIT

if ! "$PMD3" developer dvt screenshot --tunnel "$USB_UDID" "$OUTPUT" 2>"$SCREENSHOT_ERR"; then
  if grep -q "PermissionError.*Operation not permitted" "$SCREENSHOT_ERR" 2>/dev/null; then
    echo "ERROR: socket to the device tunnel was blocked by the sandbox."
    echo ""
    echo "The IPv6 link-local connection to the device tunnel address can't"
    echo "be made from inside Cursor's default sandbox. Re-invoke this script"
    echo "with required_permissions: [\"all\"] (or run it from Claude Code,"
    echo "which has no sandbox)."
    exit 5
  fi
  # Some other failure — surface the original output so the human/agent can act.
  cat "$SCREENSHOT_ERR" >&2
  exit 6
fi

if [ -f "$OUTPUT" ]; then
  echo "OK: ${OUTPUT}"
else
  echo "ERROR: Screenshot command ran but no file was created."
  echo "The device may need to Trust this computer — ask the user to tap Trust on the iPhone."
  exit 4
fi
