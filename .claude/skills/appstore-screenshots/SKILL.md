---
name: appstore-screenshots
description: Capture localized iPhone App Store screenshots from the simulator using the in-app ScreenshotHarness, show them to the user for sign-off, then push to App Store Connect via fastlane. Use when the user asks to refresh, regenerate, retake, or upload App Store screenshots.
allowed-tools: Bash(bash .claude/skills/appstore-screenshots/scripts/capture.sh:*), Bash(make appstore-push:*), Read(./iOS/fastlane/screenshots/**)
---

# App Store Screenshot Pipeline

Drives `iOS/App/ScreenshotHarness.swift` (gated by `#if targetEnvironment(simulator)`) to capture every App Store scene for every locale into `iOS/fastlane/screenshots/<locale>/iPhone-6.9/`. Then waits for explicit user sign-off before uploading via `fastlane deliver`.

See GitHub issues [#28](https://github.com/FokkeZB/GluWink/issues/28) (tracker), [#29](https://github.com/FokkeZB/GluWink/issues/29) (harness), and [#31](https://github.com/FokkeZB/GluWink/issues/31) (captions) for design context.

## Captions

Every shot has a marketing caption baked into the bottom ~20% of the PNG by `CaptionBanner.swift`. The text is pulled from `AppStore/<locale>.md` → "Screenshot captions" → iPhone table by `capture.sh` and passed to the app via `-UITest_Caption "..."`. Row number N in the table matches the `NN_` numeric prefix on the captured file.

The banner background matches the scene's brand language: green for `greenShield`, red for `redShield`, charcoal for everything else. Text renders white, 30pt heavy rounded, up to three lines (auto-scales down to 70% for tight translations).

Edit a caption in `AppStore/<locale>.md`, rerun `make appstore-screenshots` (or `capture.sh --scene X --locale Y --no-build` for a single shot), done. No separate caption field in App Store Connect — Apple removed per-screenshot captions from listings years ago, so the Markdown is the only place that matters.

To skip the banner while iterating on app UI (not for the App Store deck), pass `--no-captions`.

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
   - Glucose / carb numbers match the harness presets (greenShield: 6.4 mmol/L + 25 g; redShield: 14.8 mmol/L + 30 g). English locales display as mg/dL, everything else as mmol/L.
   - Caption matches the matching row in `AppStore/<locale>.md` → "Screenshot captions" and reads cleanly without hitting the 3-line limit.
   - Title text is in the right language and reads cleanly (titles are randomized per launch — re-run a single scene if you got an awkward one, the harness re-rolls).
   - No `SetupChecklistCard` visible on greenShield / redShield / settings / widgets (only on `setupChecklist`).
3. **Show the user a summary** with file paths and any concerns (e.g. "the redShield title came out as 'Take a look!' — want me to re-roll?"). **Do not push** without explicit sign-off.
4. **On approval:** `make appstore-push` (screenshots upload alongside metadata — `Deliverfile` is already configured with `skip_screenshots false`).

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
| Caption too long → script exits with "caption … is N chars" | Caption in `AppStore/<locale>.md` exceeds the hard limit (80 chars) | Tighten the translation or shorten the English source; the limit is set in `capture.sh` at the top |
| Status bar shows real values | `simctl status_bar override` didn't apply | Boot the sim once (`xcrun simctl boot "iPhone 17 Pro Max"`) and rerun |
| Build error about `ScreenshotHarness` | Old branch / harness file missing | Confirm `iOS/App/ScreenshotHarness.swift` exists; the App target uses synced groups so it should compile automatically |
| Setup checklist scene looks half-configured | Previous `settings` run left flags in the App Group | Rerun the whole deck (no `--scene`); the harness resets data-source / shielding flags on every launch |

## Side effects on the simulator

The settings scene writes `mockModeEnabled`, `shieldingEnabled`, and `healthKitEverDelivered` to the shared App Group so the rows render as "configured". The harness resets those flags to `false` on every non-settings launch, so running the full deck leaves the sim in a clean state. But if you capture only `--scene settings` and then launch the app normally (no `-UITest_Scene`), you'll see shielding + demo mode turned on until you uninstall/reinstall.

## What this skill does NOT do (yet)

- **Apple Watch (scene 05)**: needs the Watch simulator and the `WatchApp` scheme. Same harness pattern would work; not yet wired.
- **Auto-upload**: this skill stops at "PNGs on disk + user reviewed". The push step is the existing `make appstore-push`, which picks up the generated PNGs and uploads them alongside metadata.
