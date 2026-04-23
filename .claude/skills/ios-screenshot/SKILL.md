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

**Cursor users — invoke with `required_permissions: ["all"]`.** The capture connects to the device over an IPv6 link-local socket, which Cursor's default sandbox blocks. Without escalation the script will report exit code 5 ("socket blocked by the sandbox"). Claude Code has no sandbox, so it Just Works there.

## Exit Codes

| Code | Meaning | What to do |
|------|---------|------------|
| 0 | Success | Read the output file as an image |
| 1 | `python3` missing | Ask user: `xcode-select --install` |
| 2 | `tunneld` not reachable on `127.0.0.1:49151` | Ask user to run `make tunneld` (one-time per session) |
| 3 | tunneld is up but no device is tunnelled | Plug in / unlock / "Trust this computer" on the iPhone |
| 4 | pmd3 ran but produced no file | Tap "Trust" on the iPhone, then retry |
| 5 | Sandbox blocked the device-tunnel socket | Retry with `required_permissions: ["all"]` (Cursor only) |
| 6 | Other pmd3 failure | Read the stderr the script forwarded |

## First-Time Setup

The script auto-creates a venv at `~/.cache/ios-screenshot-venv` and installs `pymobiledevice3` on first run (~30s). Subsequent runs are fast (~2s).

The tunnel daemon needs `sudo` and must be started by the user once per session. Ask them to run:

```
make tunneld
```

`tunneld` listens on `127.0.0.1:49151`. The script checks that endpoint over plain HTTP — that check works inside the Cursor sandbox, so a sandboxed run will still surface a clean "start tunneld" message instead of failing at the actual screenshot step.

## Workflow

1. **(Cursor only)** Invoke the script with `required_permissions: ["all"]`. Skip this in Claude Code.
2. Run the script. If exit 2, ask the user to run `make tunneld` and retry. If exit 5, you forgot step 1 — retry with the permission set.
3. User confirms tunneld is running.
4. Read the image file to see the screenshot.
5. React to what you see — describe issues, suggest fixes.

## Why two permission models?

| Concern | Cursor | Claude Code |
|---------|--------|-------------|
| Allowlist (no per-call prompt) | Already covered by `bash .claude/skills/` in `.cursor/permissions.example.json` | Already covered in `.claude/settings.json` |
| Sandbox (network/syscalls) | `.cursor/sandbox.json` blocks IPv6 link-local sockets even with `networkPolicy.default: allow` — must escalate per-call with `required_permissions: ["all"]` | No sandbox, nothing to escalate |

The HTTP check at step 2 (`curl 127.0.0.1:49151`) works in the sandbox; the actual screenshot at step 4 (`pmd3 developer dvt screenshot`) does not. That asymmetry is deliberate: it means a sandboxed agent gets the *useful* error ("tunneld isn't running") instead of the *unhelpful* one ("you're sandboxed") when both are true.
