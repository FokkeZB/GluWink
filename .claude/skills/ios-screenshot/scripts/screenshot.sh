#!/bin/bash
# Take a screenshot from a USB-connected iPhone.
# Only requires: python3 (ships with Xcode / macOS CLT).
# Everything else is auto-installed in an isolated venv.
#
# Usage: screenshot.sh [output_path]
#   output_path defaults to /tmp/iphone_screenshot.png

set -euo pipefail

OUTPUT="${1:-/tmp/iphone_screenshot.png}"
VENV_DIR="${HOME}/.cache/ios-screenshot-venv"
VENV_PYTHON="${VENV_DIR}/bin/python3"
PMD3="${VENV_DIR}/bin/pymobiledevice3"

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

# --- Check tunneld is running ---
if ! pgrep -f "pymobiledevice3.*tunneld" >/dev/null 2>&1; then
  echo "ERROR: tunneld is not running."
  echo ""
  echo "Ask the user to run this in their own terminal (needs sudo, stays running):"
  echo ""
  echo "  sudo ${VENV_PYTHON} -m pymobiledevice3 remote tunneld"
  echo ""
  exit 2
fi

# --- Find the USB-connected device UDID ---
USB_UDID=$("$PMD3" usbmux list --usb 2>/dev/null | "$VENV_PYTHON" -c "import sys,json; devs=json.load(sys.stdin); print(devs[0]['UniqueDeviceID'] if devs else '')" 2>/dev/null || echo "")

if [ -z "$USB_UDID" ]; then
  echo "ERROR: No USB-connected iPhone found."
  echo "Make sure the device is plugged in via USB cable."
  exit 3
fi

# --- Take the screenshot ---
"$PMD3" developer dvt screenshot --tunnel "$USB_UDID" "$OUTPUT" 2>&1

if [ -f "$OUTPUT" ]; then
  echo "OK: ${OUTPUT}"
else
  echo "ERROR: Screenshot command ran but no file was created."
  echo "The device may need to Trust this computer — ask the user to tap Trust on the iPhone."
  exit 4
fi
