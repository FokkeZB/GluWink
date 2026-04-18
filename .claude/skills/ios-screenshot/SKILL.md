---
name: ios-screenshot
description: Capture a screenshot from a USB-connected iPhone and view it. Use when you need to see what's on the user's iPhone screen, verify iOS UI changes, check device state, or the user asks you to look at their phone. Only works with a physically connected device.
allowed-tools: Bash(bash .claude/skills/ios-screenshot/scripts/screenshot.sh:*), Read(/tmp/iphone_screenshot*)
---

# iOS Device Screenshot

Capture and view a screenshot from a USB-connected iPhone. Uses `pymobiledevice3` in an isolated venv — the only host dependency is `python3` (ships with Xcode).

## Quick Start

```bash
bash .claude/skills/ios-screenshot/scripts/screenshot.sh /tmp/iphone_screenshot.png
```

Then read the image with the Read tool on `/tmp/iphone_screenshot.png`.

## Exit Codes

| Code | Meaning | What to do |
|------|---------|------------|
| 0 | Success | Read the output file as an image |
| 1 | `python3` missing | Ask user: `xcode-select --install` |
| 2 | `tunneld` not running | Ask user to run the sudo command printed in the output (one-time per session) |
| 4 | No file created | Ask user to tap "Trust" on the iPhone, then retry |

## First-Time Setup

The script auto-creates a venv at `~/.cache/ios-screenshot-venv` and installs `pymobiledevice3` on first run (~30s). Subsequent runs are fast (~2s).

The tunnel daemon needs `sudo` and must be started by the user once per session. Ask them to run:

```
make tunneld
```

## Workflow

1. Run the script — if exit code 2, ask the user to run `make tunneld` in their terminal
2. User confirms tunneld is running
3. Retry the script
4. Read the image file to see the screenshot
5. React to what you see — describe issues, suggest fixes
