---
name: watchface-screenshots
description: Guide the owner through capturing `06_watchFace.png` — the Apple Watch face with GluWink complications — on the watchOS Simulator, one locale at a time. Use when the user asks to refresh, regenerate, retake, or capture the watch face / complication screenshots, or when `make appstore-screenshots` finishes and the Watch face shot is missing / stale. Apple provides no API to render a full watch face programmatically, so the agent can't capture this one — this skill is the hand-holding for the manual part.
allowed-tools: Bash(make watchface-prepare:*), Bash(make watchface-capture:*), Bash(bash .claude/skills/watchface-screenshots/scripts/:*), Read(./iOS/fastlane/screenshots/**), Read(./docs/assets/screenshots/**)
---

# Apple Watch Face Screenshot Capture

Walks the owner through capturing `06_watchFace.png` — the Apple Watch face with GluWink complications — from the watchOS Simulator, one locale at a time. This is the piece that `make appstore-screenshots` / `.claude/skills/appstore-screenshots/` deliberately skips: Apple exposes no API to render a full watch face programmatically (ClockKit's preview surfaces only the tile, not the surrounding face), so there's a human-in-the-loop step where the owner physically picks a face and adds complications in the simulator's UI.

This skill handles everything around that one click-and-hold — booting the sim, localising the face strings, installing the WatchApp, validating the PNG, and writing it to both the fastlane and docs trees — so the owner's entire contribution is the literal "long-press → Edit → pick GluWink" dance.

See the sibling [`appstore-screenshots`](../appstore-screenshots/SKILL.md) skill for the automated iPhone + WatchApp deck that sits alongside this.

## Why this skill exists

The broader App Store deck is driven by `iOS/App/ScreenshotHarness.swift` and `iOS/WatchApp/WatchScreenshotHarness.swift`, both invoked from `.claude/skills/appstore-screenshots/scripts/capture.sh`. That script builds, boots simulators, launches the app with `-UITest_Scene`, and grabs PNGs — end-to-end hands-free.

**Watch face screenshots don't fit that model**, for two reasons:

1. **No programmatic face renderer.** `simctl io <udid> screenshot` captures whatever's on screen, but a watch face with complications requires the face UI to be visible AND configured. There's no API — public or private — to push a face configuration into a simulator. The owner has to open the sim window and configure it by hand.
2. **Locale on the *face*, not the app.** The scripted deck passes `-AppleLanguages` as launch arguments to the WatchApp, which only affects the app's own UI. The face's weekday, date, and calendar strings come from the *system* locale. Changing that needs a reboot-the-sim-with-new-defaults dance, which this skill's `prepare.sh` does.

So this skill is two things: a Makefile sandwich that handles the boring parts (boot, localise, build, install, screenshot, validate, save to both trees), and a crisp instruction sheet the agent reads to the owner for the minute of manual UI work in between.

## Requirements

- **46mm Apple Watch simulator** (Series 10 or 11). That's the `APP_WATCH_SERIES_10` / 416×496 px bucket. fastlane `deliver` routes the PNG to the App Store Connect "Apple Watch Series 10" tier purely by pixel dimensions — any other case size is rejected at upload time. `capture.sh` validates this and fails fast. (Apple discontinued the 45mm case with Series 10 in late 2024; the old 396×484 `APP_WATCH_SERIES_7` tier is for Series 7/8/9 only and we no longer target it.)
- **Xcode must be installed** — the scripts shell out to `xcodebuild`, `xcrun simctl`, and `sips`.
- The WatchApp target must build cleanly. The scripts use a dedicated DerivedData path (`/tmp/glucoach-screenshots-dd`) so they don't fight a concurrent Xcode session.

## Quick Start

```bash
# One locale, full build (first run)
make watchface-prepare LOCALE=en-US
#    ... owner configures the face in the sim UI ...
make watchface-capture LOCALE=en-US

# Switch locale without rebuilding (WatchApp binary is the same across locales)
make watchface-prepare LOCALE=nl-NL NO_BUILD=1
#    ... owner re-opens Edit → picks complications again on the NL face ...
make watchface-capture LOCALE=nl-NL

# Different Watch sim (default is 'Apple Watch Series 11 (46mm)')
make watchface-prepare LOCALE=en-US WATCH_DEVICE='Apple Watch Series 10 (46mm)'
```

The PNGs land flat alongside the iPhone captures:

```
iOS/fastlane/screenshots/<locale>/06_watchFace.png    ← App Store deck
docs/assets/screenshots/<locale>/06_watchFace.png     ← Marketing site
```

`docs/scripts/sync-screenshots.sh` intentionally skips `06_watchFace` (it's not a copy target — it's an *alternative* to the automated sync), so both files need to be written directly. `capture.sh` does both.

## Workflow

The agent walks the owner through this one locale at a time. For each locale defined in `AppStore/*.md` (currently `en-US` and `nl-NL`):

### 1. Prepare the simulator

```bash
make watchface-prepare LOCALE=<locale>
```

`prepare.sh` does the following, in order:

1. Looks up the 46mm Watch sim's UDID by name. If not found, it lists the available sims and exits — the owner needs to install a 46mm runtime via Xcode → Settings → Platforms.
2. **If the sim is already booted, shuts it down.** This matters: `defaults write -g AppleLanguages` on a running sim doesn't reliably flow through to already-drawn face UI. Cold-boot → defaults applied → face renders in the target locale.
3. Runs `xcrun simctl spawn <udid> defaults write -g AppleLanguages/AppleLocale` with the locale split (`en-US` → `AppleLanguages=(en)`, `AppleLocale=en_US`).
4. Boots the sim and waits for it to be ready.
5. Builds the WatchApp for the watch sim destination (skipped with `NO_BUILD=1` — useful when flipping between locales).
6. Installs the WatchApp bundle.
7. Launches the WatchApp once (with `-UITest_Scene watchApp` so the harness writes demo data into the shared App Group, so the complication tile has real values to render instead of the "--" placeholder) and immediately terminates it. Leaves the sim on the face.
8. `open -a Simulator` to bring the window to the front.
9. Prints the manual-steps cheat sheet (see next section).

### 2. Owner configures the face (manual)

Read these steps aloud to the owner — they're printed by `prepare.sh` but it's worth surfacing so the agent is seen to be in control of the handoff:

1. If the Simulator window shows the WatchApp, press the Digital Crown (Hardware → Home, or Cmd-Shift-H) to get back to the watch face.
2. **Long-press** (click-and-hold) the watch face. The face picker appears.
3. Tap **Edit**.
4. Swipe left to the **Complications** pane.
5. Tap a complication slot, scroll the picker to **GluWink**, choose the tile — Glucose, Carbs, or Combined. Add at least one; the whole marketing point is "complications on every face."
6. Press the Digital Crown twice: once to confirm the complication, once to return to the face.
7. Confirm the face now shows:
   - Weekday / date in the target locale (`Mon 27` for en-US, `ma 27` for nl-NL, `lu 27` for it-IT, etc.).
   - At least one GluWink complication rendering **real values** (not the `--` placeholder). If it's still `--`, give it a few seconds — the widget timeline is populated asynchronously after install.
8. Leave the sim on the face (don't tap into the app, don't start any other workflow).

**Agent:** after printing the cheat sheet, wait for the owner to confirm they've finished the face setup. Don't proceed to capture automatically.

### 3. Capture the screenshot

```bash
make watchface-capture LOCALE=<locale>
```

`capture.sh` does:

1. Looks up the 46mm Watch sim UDID (same way as `prepare.sh`).
2. Verifies the sim is in state `Booted` — errors out with a clear message if not (prevents silently overwriting the good PNG with a black frame).
3. `xcrun simctl io <udid> screenshot` into `iOS/fastlane/screenshots/<locale>/06_watchFace.png`.
4. Runs `sips -g pixelWidth -g pixelHeight` to confirm 416×496. **Any other size deletes the file and errors out** — the most common causes: Ultra 3 49mm (422×514), 42mm (374×446), SE 44mm (396×484 — the old 45mm bucket), SE 40mm (324×394). All of those route to different fastlane tiers.
5. Copies the validated PNG to `docs/assets/screenshots/<locale>/06_watchFace.png`.
6. Prints the two output paths and the validated dimensions.

### 4. Review

Agent reads both PNGs back through the client (if supported) or asks the owner to open them in Finder. Eyeball:

- **Localisation lands.** Weekday / date string, any calendar text, any "Hello"/"Activity" system strings — all in the target locale.
- **At least one GluWink complication is visible** and shows real values (`6.4 mmol/L`, `25 g`, etc. — not `--`).
- **Face choice reads as GluWink.** The app's brand is the three-color attention signal, so green or orange faces sell the product best; red is fine too if the demo data happens to be critical, but it's the edge case. Avoid faces that swallow the complication tile (e.g. very dense analog faces where the tile is the size of a grain of rice) — pick Modular, Modular Duo, Infograph, or Infograph Modular for clarity.
- **No identifying content.** Calendar events, contacts, activity rings with personal data — delete or switch to a different face before capturing.

If anything looks off, re-run steps 2–3 for that locale.

### 5. Repeat per locale

Loop through every locale present in `AppStore/*.md`. Between locales:

```bash
make watchface-prepare LOCALE=<next-locale> NO_BUILD=1
```

The `NO_BUILD=1` flag matters across the loop — rebuilding WatchApp once per locale is gratuitous, the binary is identical. Only drop it if you've changed WatchApp source since the last prepare.

### 6. Commit

Once every locale is covered, the changed files should be (at minimum):

```
iOS/fastlane/screenshots/<locale>/06_watchFace.png  (new/updated for each locale)
docs/assets/screenshots/<locale>/06_watchFace.png   (new/updated for each locale)
```

Invoke the [`git-commit`](../git-commit/SKILL.md) skill to stage and commit with a clear message (`chore(appstore): refresh watch face complication screenshots` or similar).

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Apple Watch simulator '...' not found` | No 46mm watch runtime installed, or the name has rotated | `xcrun simctl list devices available` to see what's installed. Pass `WATCH_DEVICE='...'` to either target. Install a new runtime via Xcode → Settings → Platforms if needed. |
| Watch face stays in English after `LOCALE=nl-NL` prepare | `defaults write` didn't flow through — the sim was already booted when the script ran | Re-run `make watchface-prepare LOCALE=nl-NL` — the script force-shuts-down a running sim before writing defaults, but a concurrent Xcode session may have re-booted it. Quit Xcode's Devices & Simulators window if so. |
| Complication tile shows `--` instead of a value | The WatchScreenshotHarness hadn't seeded demo data yet, or the widget timeline's first refresh is pending | Wait 5-10 seconds on the face, then capture. If still `--`, re-run `prepare.sh` — the priming launch may have been too short. |
| Complication renders **orange** (stale / needs-attention) when the seeded value should be green | The host-level `/private/tmp/dev.simulator.watch-bridge.json` file written by a previous iPhone Simulator session is overriding the harness's App Group writes. `WatchDataManager.content()` checks this bridge first, so a stale `currentGlucose` / `glucoseFetchedAt` / lowered threshold from an old session poisons the capture even though the harness seeded fresh values moments earlier. | `prepare.sh` scrubs both `/private/tmp/dev.simulator.watch-bridge.json` and `/tmp/dev.simulator.watch-bridge.json` before boot — so just re-running prepare fixes it. If the orange persists after prepare, manually `rm -f /private/tmp/dev.simulator.watch-bridge.json /tmp/dev.simulator.watch-bridge.json` and re-run `make watchface-prepare LOCALE=…`. The bridge is *only* an iOS/watchOS Simulator bypass for WatchConnectivity; safe to delete at any time. |
| GluWink isn't listed in the Edit → Complications picker | `chronod` cached the extension list at a previous boot and hasn't rescanned since `WatchWidget.appex` was installed | `prepare.sh` reboots the sim post-install exactly to avoid this, but if it still hits, reboot the sim manually (`xcrun simctl shutdown <udid> && xcrun simctl boot <udid>`) and give it 10s before retrying Edit. Also: GluWink only registers `.accessoryRectangular`, `.accessoryCircular`, and `.accessoryCorner` — faces whose slots are all `.accessoryInline` (e.g. the "Utility" inline strip) will never show it, by design. |
| `captured PNG is 422x514` | Sim is an Apple Watch Ultra (49mm), not a 46mm | Switch to a 46mm sim with `WATCH_DEVICE='Apple Watch Series 11 (46mm)'`. Ultra has its own App Store Connect tier which we don't currently target. |
| Capture is a black frame | Sim was not actually on the face, or the simulator host process lost state | Bring Simulator.app forward, confirm the face is visible, re-run capture. |
| `make appstore-push` complains the Watch deck is incomplete | Only one of the two output paths got written (older capture flow) | Re-run this skill — `capture.sh` writes both. Alternatively, copy the committed `docs/assets/screenshots/<locale>/06_watchFace.png` into `iOS/fastlane/screenshots/<locale>/` by hand. |

## What this skill does NOT do

- **Push to App Store Connect.** That's `make appstore-push` (or `make appstore-screenshots` for the full-deck wrapper). This skill stops at "PNGs on disk, validated, owner reviewed."
- **Capture anything other than `06_watchFace.png`.** The rest of the deck is the `appstore-screenshots` skill's territory.
- **Decide which face to use.** Marketing judgement stays with the owner — see the review checklist for the constraints the face must satisfy, but the pick is theirs.
- **Capture on a physical Watch.** `xcrun simctl io` is simulator-only. If the owner wants a device-bezel shot (arguably higher-quality marketing asset) they capture it by hand through Xcode → Devices & Simulators → Take Screenshot and commit it at the same two paths — `capture.sh`'s job is only simulator-derived PNGs.
