---
name: appstore-screenshots
description: Capture localized iPhone and Apple Watch App Store screenshots from the simulators using the in-app ScreenshotHarness / WatchScreenshotHarness, show them to the user for sign-off, then push to App Store Connect via fastlane. Use when the user asks to refresh, regenerate, retake, or upload App Store screenshots.
allowed-tools: Bash(bash .claude/skills/appstore-screenshots/scripts/capture.sh:*), Bash(make appstore-push:*), Read(./iOS/fastlane/screenshots/**)
---

# App Store Screenshot Pipeline

Drives `iOS/App/ScreenshotHarness.swift` (iPhone, gated by `#if targetEnvironment(simulator)`) and `iOS/WatchApp/WatchScreenshotHarness.swift` (Apple Watch, same gate) to capture every App Store scene for every locale into `iOS/fastlane/screenshots/<locale>/` (flat — no device-size subfolder; fastlane `deliver` buckets by pixel dimensions, not path, so a Watch PNG at 396×484 lands in the 45mm bucket alongside the iPhone PNGs at 1320×2868 in the same locale folder. See QUIRKS.md → "Fastlane deliver ignores device-size subfolders" and `deliver/lib/deliver/loader.rb`). Then waits for explicit user sign-off before uploading via `fastlane deliver`.

See GitHub issues [#28](https://github.com/FokkeZB/GluWink/issues/28) (tracker), [#29](https://github.com/FokkeZB/GluWink/issues/29) (harness), and [#31](https://github.com/FokkeZB/GluWink/issues/31) (captions) for design context.

## Captions

Every shot has a marketing caption baked into the bottom ~20% of the PNG by `CaptionBanner.swift`. The text is pulled from `AppStore/<locale>.md` → "Screenshot captions" → iPhone table by `capture.sh` and passed to the app via `-UITest_Caption "..."`. Row number N in the table matches the `NN_` numeric prefix on the captured file.

The banner background matches the scene's brand language: green for `greenShield`, brand orange (`#F5A623`, same shade as `AppIcon-Orange`) for `orangeShield`, red for `redShield`, charcoal for everything else. Text renders white, 30pt heavy rounded, up to three lines (auto-scales down to 70% for tight translations).

Edit a caption in `AppStore/<locale>.md`, rerun `make appstore-screenshots` (or `capture.sh --scene X --locale Y --no-build` for a single shot), done. No separate caption field in App Store Connect — Apple removed per-screenshot captions from listings years ago, so the Markdown is the only place that matters.

To skip the banner while iterating on app UI (not for the App Store deck), pass `--no-captions`.

## Scenes

| # | Scene name (`-UITest_Scene`) | Marketing intent | Captured by this skill? |
|---|---|---|---|
| 01 | `greenShield` | All clear — friendly green face, glucose + carbs visible | Yes |
| 02 | `orangeShield` | Needs attention — orange face, glucose just above the high threshold, first check-in row pre-ticked, shield dismissible | Yes |
| 03 | `redShield` | Critical — red face, glucose ≥ critical threshold, check-in button hidden, "shield cannot be dismissed until glucose drops below X" subtitle visible | Yes |
| 04 | `widgets` | Home Screen widgets (small × 2 + medium + large, mixed states) | Yes — via `WidgetShowcaseView` which renders the real SharedKit tiles |
| 05 | `settings` | Parent / main-app view — Settings list (Shielding On, data sources, glucose unit) | Yes |
| 06 | `watchFace` | Apple Watch face with GluWink complications in context | **No — manual** (see "Manual shots" below) |
| 07 | `setupChecklist` | Welcome panel + "Pick a data source" / "Configure features" rows | Yes |
| 07 | `watchApp` | Apple Watch WatchApp UI — glucose, carbs, relative timestamps | Yes — via `WatchScreenshotHarness` on the watchOS simulator |

Scenes 01-03 deliberately sit adjacent so the App Store reviewer scrolling the deck sees the full traffic-light story (green → orange → red / critical) before anything else. `07_setupChecklist` (iPhone bucket) and `07_watchApp` (Watch bucket) share the numeric prefix but sit in different device tiers on ASC, so they don't collide — the prefix orders files inside each tier, and fastlane's `AppScreenshot.calculate_display_type` routes to the tier purely on pixel dimensions.

Locales come from `AppStore/<locale>.md`. Today: `en-US`, `nl-NL`. Adding a new locale Markdown file automatically adds it to the capture matrix.

## Manual shots

**`06_watchFace.png` — Apple Watch face with GluWink complications in context.** Apple exposes no API to render a full watch face programmatically — ClockKit's complication preview renders the tile, not the surrounding face, and `xcrun simctl io screenshot` on the watch sim captures whatever the WatchApp draws (so the same hard wall). The owner therefore captures this one by hand — on device, not the simulator if possible, for the real bezel / sensor look.

Requirements:
- **45mm Apple Watch Series 7 / 8 / 9 / 10 / 11.** That's the 396×484 px bucket (`APP_WATCH_SERIES_7` in fastlane `deliver`), which App Store Connect treats as "Apple Watch Series 7 (45mm)". Other case sizes won't match the bucket and `deliver` will reject them.
- **Complications visible.** Whichever face the owner uses, at least one GluWink complication (glucose or carb tile) should be obvious — the whole marketing point.
- **One shot per locale.** The watchOS system strings shown on the face (weekday, calendar "nothing scheduled", etc.) come from the watch's own language setting, so the EN and NL versions are separate captures.

Commit to both sides of the pipeline:
- `docs/assets/screenshots/<locale>/06_watchFace.png` — site carousel's Watch slide.
- `iOS/fastlane/screenshots/<locale>/06_watchFace.png` — App Store Connect Watch deck (alongside the auto-captured `07_watchApp.png`).

`docs/scripts/sync-screenshots.sh` skips this file in both copy and `--check` modes so it doesn't fight the manual capture.

## Quick Start

```bash
# Capture every scene × every locale (one build per platform, ~60s end-to-end)
make appstore-screenshots

# Iterate on one iPhone scene without rebuilding
bash .claude/skills/appstore-screenshots/scripts/capture.sh \
    --scene redShield --locale en-US --no-build

# Iterate on the Apple Watch scene only
bash .claude/skills/appstore-screenshots/scripts/capture.sh \
    --scene watchApp --locale en-US --no-build

# iPhone only (e.g. no 45mm Watch sim installed on this machine)
bash .claude/skills/appstore-screenshots/scripts/capture.sh --skip-watch

# Different iPhone simulator (default is "iPhone 17 Pro Max", the 6.9" device)
bash .claude/skills/appstore-screenshots/scripts/capture.sh --device "iPhone 16 Pro Max"

# Different Watch simulator (default is "Apple Watch Series 10 (45mm)")
bash .claude/skills/appstore-screenshots/scripts/capture.sh --watch-device "Apple Watch Series 11 (45mm)"
```

`make appstore-screenshots` is the short alias for the full-deck capture. Use the raw `capture.sh` path for `--scene` / `--locale` / `--device` / `--watch-device` / `--no-build` / `--skip-watch`.

The script writes to `iOS/fastlane/screenshots/<locale>/<NN>_<scene>.png` (flat — iPhone and Watch PNGs coexist in the locale folder) and locks the iPhone simulator's status bar to 9:41, full battery, full bars before each iPhone shot. Watch shots don't get a status-bar override: watchOS's face doesn't have the iOS-style bar, and the app fills the full screen.

## Workflow

1. **Capture.** Run the script with no args. Use `--no-build` if a fresh `xcodebuild` already happened in this session.
2. **Review every PNG.** Read each file in the agent client and check:
   - Status bar reads `9:41`, full bars, full battery (charged charging glyph).
   - Glucose / carb numbers match the harness presets (greenShield: 6.4 mmol/L + 25 g; orangeShield: 14.8 mmol/L + 30 g; redShield: 21.2 mmol/L — critical, above the 20.0 default). English locales display as mg/dL, everything else as mmol/L.
   - `redShield` has **no** Continue / check-in button — the critical path hides it, and the subtitle reads "shield cannot be dismissed until your glucose is below …". If you see a dismiss button, the critical preset regressed.
   - `orangeShield` **does** show the check-in list with the first row ticked, and the face is the brand orange shade (not red, not system orange).
   - Caption matches the matching row in `AppStore/<locale>.md` → "Screenshot captions" and reads cleanly without hitting the 3-line limit.
   - Title text is in the right language and reads cleanly (titles are randomized per launch — re-run a single scene if you got an awkward one, the harness re-rolls).
   - No `SetupChecklistCard` visible on greenShield / orangeShield / redShield / settings / widgets (only on `setupChecklist`).
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
| `SetupChecklistCard` showing on greenShield / orangeShield / redShield | Build is stale (harness fix not yet compiled) | Drop `--no-build` and rerun |
| `redShield` shows a "Continue" / check-in button | Glucose preset fell below the critical threshold (e.g. a preset edit, or a lowered threshold) | Confirm `ScreenshotHarness.redShield.glucose` is ≥ `CriticalGlucoseThreshold.default` and rerun |
| Caption too long → script exits with "caption … is N chars" | Caption in `AppStore/<locale>.md` exceeds the hard limit (80 chars) | Tighten the translation or shorten the English source; the limit is set in `capture.sh` at the top |
| Status bar shows real values | `simctl status_bar override` didn't apply | Boot the sim once (`xcrun simctl boot "iPhone 17 Pro Max"`) and rerun |
| Build error about `ScreenshotHarness` | Old branch / harness file missing | Confirm `iOS/App/ScreenshotHarness.swift` exists; the App target uses synced groups so it should compile automatically |
| Setup checklist scene looks half-configured | Previous `settings` run left flags in the App Group | Rerun the whole deck (no `--scene`); the harness resets data-source / shielding flags on every launch |

## Side effects on the simulator

The settings scene writes `mockModeEnabled`, `shieldingEnabled`, and `healthKitEnabled` to the shared App Group so the rows render as "configured". The harness resets those flags to `false` on every non-settings launch (keeping `mockModeEnabled` on only when the scene has seeded Demo values via `UnifiedDataReader`), so running the full deck leaves the sim in a clean state. But if you capture only `--scene settings` and then launch the app normally (no `-UITest_Scene`), you'll see shielding + demo mode turned on until you uninstall/reinstall.

## What this skill does NOT do (yet)

- **Auto-upload**: this skill stops at "PNGs on disk + user reviewed". The push step is the existing `make appstore-push`, which picks up the generated PNGs and uploads them alongside metadata.
- **Watch face screenshot capture**: `06_watchFace.png` is manually captured by the owner (see "Manual shots" above). Apple provides no API to render a complete watch face with complications, and `simctl io screenshot` on the watch sim captures only the app's own UI.
