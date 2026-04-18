---
name: appstore-screenshots
description: Capture localized iPhone App Store screenshots from the simulator using the in-app ScreenshotHarness, show them to the user for sign-off, then push to App Store Connect via fastlane. Use when the user asks to refresh, regenerate, retake, or upload App Store screenshots.
allowed-tools: Bash(bash .claude/skills/appstore-screenshots/scripts/capture.sh:*), Bash(make appstore-push:*), Read(./iOS/fastlane/screenshots/**)
---

# App Store Screenshot Pipeline

Drives `iOS/App/ScreenshotHarness.swift` (gated by `#if targetEnvironment(simulator)`) to capture every App Store scene for every locale into `iOS/fastlane/screenshots/<locale>/iPhone-6.9/`. Then waits for explicit user sign-off before uploading via `fastlane deliver`.

See GitHub issues [#28](https://github.com/FokkeZB/GluWink/issues/28) (tracker) and [#29](https://github.com/FokkeZB/GluWink/issues/29) (harness) for design context.

## Scenes

| # | Scene name (`-UITest_Scene`) | Marketing intent | Captured by this skill? |
|---|---|---|---|
| 01 | `greenShield` | All clear — friendly green face, glucose + carbs visible | Yes |
| 02 | `redShield` | Needs attention — red face, first check-in row pre-ticked | Yes |
| 03 | `widgets` | Home Screen widgets (small × 2 + medium + large, mixed states) | Yes — via `WidgetShowcaseView` which renders the real SharedKit tiles |
| 04 | `settings` | Parent / main-app view — Settings list (Shielding On, data sources, glucose unit) | Yes |
| 05 | `watch` | Apple Watch app + complications | **No** — needs the Watch simulator path, follow-up |
| 06 | `setupChecklist` | Welcome panel + "Pick a data source" / "Configure features" rows | Yes |

Locales come from `AppStore/<locale>.md`. Today: `en-US`, `nl-NL`. Adding a new locale Markdown file automatically adds it to the capture matrix.

## Quick Start

```bash
# Capture every scene × every locale (one build, ~30s end-to-end)
make appstore-screenshots

# Iterate on one scene without rebuilding — drop down to the script directly
bash .claude/skills/appstore-screenshots/scripts/capture.sh \
    --scene redShield --locale en-US --no-build

# Different simulator (default is "iPhone 17 Pro Max", the 6.9" device)
bash .claude/skills/appstore-screenshots/scripts/capture.sh --device "iPhone 16 Pro Max"
```

`make appstore-screenshots` is the short alias for the full-deck capture. Use the raw `capture.sh` path for the `--scene` / `--locale` / `--device` / `--no-build` flags.

The script writes to `iOS/fastlane/screenshots/<locale>/iPhone-6.9/<NN>_<scene>.png` and locks the simulator status bar to 9:41, full battery, full bars before each shot.

## Workflow

1. **Capture.** Run the script with no args. Use `--no-build` if a fresh `xcodebuild` already happened in this session.
2. **Review every PNG.** Read each file in the agent client and check:
   - Status bar reads `9:41`, full bars, full battery (charged charging glyph).
   - Glucose / carb numbers match the harness presets (greenShield: 6.4 mmol/L + 25 g; redShield: 14.8 mmol/L + 30 g).
   - Title text is in the right language and reads cleanly (titles are randomized per launch — re-run a single scene if you got an awkward one, the harness re-rolls).
   - No `SetupChecklistCard` visible on greenShield / redShield / settings / widgets (only on `setupChecklist`).
3. **Show the user a summary** with file paths and any concerns (e.g. "the redShield title came out as 'Take a look!' — want me to re-roll?"). **Do not push** without explicit sign-off.
4. **On approval:** flip `iOS/fastlane/Deliverfile` line 16 from `skip_screenshots true` to `false` (and any other steps from issue #28 → "Flipping the upload switch") if not already done, then `make appstore-push`.

## Re-rolling a single scene

Titles are picked from a numbered list at render time (see `QUIRKS.md` → "Numbered string lists for random titles"). To re-roll without rebuilding:

```bash
bash .claude/skills/appstore-screenshots/scripts/capture.sh \
    --scene greenShield --locale en-US --no-build
```

Repeat until the title reads well in marketing context.

## Adding a new locale

1. Create `AppStore/<locale>.md` (see `AppStore/README.md` → "Contributing a new translation").
2. Re-run `capture.sh`. The script discovers the new locale automatically.
3. Confirm Apple's strings (system buttons, time format) localized correctly. If not, the system language code (`<locale>` minus the region) may not be supported by iOS — pick the closest one and override in the script's `language_code_for_locale` helper.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `CoreSimulatorService connection became invalid` | simctl can't talk to the host service | Run any `xcrun simctl …` once outside the agent sandbox; opening Xcode also fixes it |
| Captures show wrong language | `-AppleLanguages` ignored by some screens | Confirm the locale file exists in the iOS bundle (`iOS/App/<lang>.lproj/`) |
| `SetupChecklistCard` showing on greenShield / redShield | Build is stale (harness fix not yet compiled) | Drop `--no-build` and rerun |
| `home` scene looks identical to `greenShield` | They are, intentionally — see scene table | Either pick one in App Store Connect or evolve the `home` preset in `ScreenshotHarness.swift` |
| Status bar shows real values | `simctl status_bar override` didn't apply | Boot the sim once (`xcrun simctl boot "iPhone 17 Pro Max"`) and rerun |
| Build error about `ScreenshotHarness` | Old branch / harness file missing | Confirm `iOS/App/ScreenshotHarness.swift` exists; the App target uses synced groups so it should compile automatically |
| Setup checklist scene looks half-configured | Previous `settings` run left flags in the App Group | Rerun the whole deck (no `--scene`); the harness resets data-source / shielding flags on every launch |

## Side effects on the simulator

The settings scene writes `mockModeEnabled`, `shieldingEnabled`, and `healthKitEverDelivered` to the shared App Group so the rows render as "configured". The harness resets those flags to `false` on every non-settings launch, so running the full deck leaves the sim in a clean state. But if you capture only `--scene settings` and then launch the app normally (no `-UITest_Scene`), you'll see shielding + demo mode turned on until you uninstall/reinstall.

## What this skill does NOT do (yet)

- **Apple Watch (scene 05)**: needs the Watch simulator and the `WatchApp` scheme. Same harness pattern would work; not yet wired.
- **Caption rendering / device frames**: tracked under issue #31 (`fastlane frameit` driven from the Markdown captions).
- **Auto-upload**: this skill stops at "PNGs on disk + user reviewed". The push step is the existing `make appstore-push`, which only includes screenshots once `Deliverfile` line 16 flips to `skip_screenshots false` (see issue #28 → "Flipping the upload switch").
