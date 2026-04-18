---
name: ios-deploy
description: Install the app on a USB-connected iPhone from CLI. Use when the user asks to deploy, install, or test on their phone. Building is handled by the Xcode MCP BuildProject tool.
---

# iOS Device Install

Install a built app on a connected iPhone using `devicectl`. Building should be done via the Xcode MCP `BuildProject` tool first.

## Install

```bash
make install
```

Installs the last build on the connected iPhone. The device ID is auto-detected.

## Full Deploy (build + install)

If the Xcode MCP is unavailable (Xcode not running), fall back to:

```bash
make deploy
```

This runs `xcodebuild` then `devicectl` in sequence.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `No matching destination` | No iPhone connected | Ask user to connect their iPhone via USB |
| Signing error | Provisioning expired or wrong team | User must open Xcode once to fix signing |
| `DEVICE_ID` empty | `devicectl` can't find device | Ask user to unlock their iPhone and trust this Mac |
| `APP_PATH` empty | No previous build exists | Build first via `BuildProject` MCP tool or `make build` |

## Workflow

1. Build via Xcode MCP `BuildProject` tool (preferred) or `make build` (fallback)
2. Run `make install` to push to the device
3. If it fails, check the error output and consult the troubleshooting table
4. Optionally use the `ios-screenshot` skill to verify the result on device
