# GluWink — Quirks & Gotchas

## Screen Time API

### ShieldConfiguration is extremely limited
Only: title (text + color), subtitle (text + color), icon, primary button (label + color + background color), secondary button (same), background blur style. No custom views, no fonts, no interactive elements, no live countdowns, no disabled buttons.

### Secondary button always closes the app
The secondary button ("Close App") dismisses the shielded app without removing the shield. There is no callback for secondary button presses in `ShieldActionDelegate` — only primary button fires `handle(action:)`.

### ShieldActionResponse.defer vs .close
- `.defer` dismisses the shield view but keeps the shield armed — next time the user opens the app, the shield shows again (and `ShieldConfigurationDataSource` is re-queried).
- `.close` removes the shield entirely via `ManagedSettingsStore`.

### ShieldConfigurationDataSource is called each time the shield appears
Including after a `.defer`. This is useful — we re-compute the display (e.g. showing "I've done this" after attention was deferred).

### ManagedSettingsStore persists across reboots
Shields survive device restarts. No need to re-apply on boot.

### DeviceActivityMonitor extension survives reboots
Scheduled intervals persist. The extension fires at the next boundary after reboot.

### Minimum DeviceActivityMonitor interval is 15 minutes
Anything shorter throws `MonitoringError.intervalTooShort`. This is a hard iOS limit. There is no reliable way for a third-party app to detect device unlock from the background — `protectedDataDidBecomeAvailable` only fires if the app process is alive in memory, and iOS can kill suspended apps at any time. Re-arming shields therefore relies entirely on DeviceActivityMonitor intervals (which run as a system extension, independent of the app process).

### Extensions cannot access HealthKit or network
ShieldConfig, ShieldAction, and DeviceActivityMonitor extensions have no HealthKit or network access. All data must be pre-fetched by the main app and stored in the App Group.

### Extensions have very limited memory
Keep shield UI simple. No heavy images or complex view hierarchies.

### No simulator testing for Screen Time
Screen Time APIs only work on physical devices. `ShieldingActiveView` uses mock data on simulator builds to iterate on shield content without a physical device.

### .individual authorization works for self-shielding
Tested 2026-04-13: `requestAuthorization(for: .individual)` succeeds on a non-child device, shields apply, `FamilyActivityPicker` works, and `DeviceActivityMonitor` schedules intervals — all without Family Sharing. Some debug logs appear (`usermanagerd.xpc` invalidation, `LaunchServices` permission denied) but they're harmless noise from the Screen Time framework, not errors from our code.

### .child authorization fails silently without Family Sharing
On a device that isn't a child member of a Family Sharing group, `.child` authorization throws an error. The app catches this and falls back to `.individual`. The error message is not user-friendly (Apple internal domain), which is why we don't surface it.

### Family Controls Distribution requires Apple's manual review (form is short, wait is real)
The `com.apple.developer.family-controls` entitlement is one of Apple's "restricted capabilities". Apple grants the **Development** variant automatically to any team, so dev builds and Run-on-device work out of the box. The **Distribution** variant — needed for any App Store / TestFlight build — has to be requested per team at https://developer.apple.com/contact/request/family-controls-distribution/.

The form itself is short — just name, email, team ID, and acceptance of the Apple Developer License Agreement attesting that the app's primary purpose is one of:

1. parental supervision of children's app usage via Family Sharing, or
2. an individual managing their own device for focus, productivity, or personal device-usage management.

There is **no description field, no use-case essay, no demo upload** — the form was simplified, but it is still **manually reviewed**. After clicking *Get Entitlement*, the confirmation page reads:

> Thank you for your submission. We'll review your request and contact you soon with a status update.

Approval lands by email and typically takes days to a few weeks. Resubmitting the form does not speed it up. The auto-generated **Distribution** provisioning profile only picks up the entitlement after that email arrives.

The Apple Developer License Agreement clauses on the form make the limits explicit: no ad blocking, no organisational/MDM use, no managing another adult's device, no sharing the data received through the framework with advertisers or data brokers. Worth re-reading before submitting because **App Store Review** evaluates the shipped app against the same purposes under [guideline 5.5](https://developer.apple.com/app-store/review/guidelines/#5.5). GluWink fits both attested buckets cleanly (parent-managing-child + adult-self-managing diabetes check-in). Spell the medical use case out in App Review notes (see `AppStore/README.md` → Production checklist) so the reviewer doesn't have to guess.

Symptom when the request hasn't been approved yet: `xcodebuild archive` succeeds, then `xcodebuild -exportArchive` fails with one error per Family-Controls-using target:

```
error: exportArchive Provisioning profile "iOS Team Store Provisioning Profile: nl.fokkezb.GluWink.ShieldConfig" doesn't include the Family Controls (Development) capability.
error: exportArchive Provisioning profile "iOS Team Store Provisioning Profile: nl.fokkezb.GluWink.ShieldConfig" doesn't include the com.apple.developer.family-controls entitlement.
```

The "(Development)" wording is misleading — it means the auto-generated Store profile is *limited to* the Development variant of the entitlement (which is all Apple lets it carry without approval), not that the binary asked for a Development entitlement. There is no code workaround: removing the entitlement gates out the entire shielding feature, and ad-hoc / enterprise export can't reach TestFlight. The only path is the Apple form, then re-running `make appstore-beta` once the approval email arrives — `-allowProvisioningUpdates` regenerates the Store profile with the entitlement on the next archive. Targets affected: `App`, `ShieldConfig`, `ShieldAction`, `DeviceActivityMonitor`.

### Passphrase stored in Keychain, not App Group
The settings passphrase is stored in the device Keychain (SHA-256 hash + random salt, 48 bytes total). It is NOT in App Group UserDefaults — extensions don't need it, and Keychain is encrypted at rest. `kSecAttrAccessibleAfterFirstUnlock` ensures it survives backgrounding and reboots but requires the device to have been unlocked at least once.

### SwiftUI onChange unreliable for Bool toggles with multiple handlers
When a view has many `.onChange(of:)` handlers that all call the same save function, Bool toggle changes may not persist. The handler for one property can be swallowed or overridden by cascading calls from other handlers (e.g., `FamilyActivityPicker` selection changes triggered by `reevaluateShields()`). Fix: use a custom `Binding(get:set:)` on Toggle/Picker controls that saves directly in the setter, bypassing `onChange` entirely. Keep `onChange` only for Slider values where intermediate calls are acceptable.

## Xcode / Build

### fileSystemSynchronizedGroups
Files must be physically inside the synced folder to auto-compile for that target. `ShieldContent.swift` lives in `App/` (auto-compiled for main app) but has manual target membership for ShieldConfig.

### Canvas previews + Form = hangs
Using `Form` in Xcode Canvas previews causes the preview to hang on any state change (spinner appears indefinitely). Replaced with `VStack` or just use the Simulator instead.

### xcconfig can't have colons in values
`CARB_GRACE_TIME = 09:30` causes parsing issues. Split into separate `CARB_GRACE_HOUR` and `CARB_GRACE_MINUTE` variables.

### AppIcon assets aren't loadable as regular images
`Image(.appIcon)` and `UIImage(named: "AppIcon")` don't work — `.appiconset`s are processed into the per-device icon slots and aren't addressable by name at runtime. To render an icon variant inside the app (or pass it to a `ShieldConfiguration`), add a sibling `.imageset` (or a raw bundle PNG for non-app targets) with a copy of the artwork.

The home-screen icon is fixed to `AppIcon` — we do **not** call `UIApplication.shared.setAlternateIconName()` and there are no alternate `.appiconset`s. See `AGENTS.md` → "App Icon Variants" for the full convention.

### Info.plist string values from xcconfig
All config values flow through xcconfig → Info.plist as strings (even numbers). Extensions read them with `Bundle.main.object(forInfoDictionaryKey:) as! String` then parse. Force-unwrap is intentional — missing config should crash loudly during development.

## Localization

### Shield strings live in the ShieldConfig extension bundle
Localized strings for the shield UI are in `ShieldConfig/en.lproj/Localizable.strings` and `nl.lproj/`. `ShieldingActiveView` loads them at runtime from the embedded extension bundle: `Bundle.main.builtInPlugInsURL?.appendingPathComponent("ShieldConfig.appex")`.

### Numbered string lists for random titles
Positive and attention titles use numbered keys (`shield.positiveTitle.0`, `.1`, `.2`, etc.) loaded by `ShieldContent.Strings.loadList()` which iterates until a key returns itself (not found). Cap is 20.

## Widgets

### Lock Screen accessory widgets cannot show custom colors
iOS renders accessory widgets (circular, rectangular, inline) in a desaturated vibrancy style. Custom `.foregroundStyle(.red)` or `.green` is stripped to match the Lock Screen tint. There is no API to force true red/green. Use `.widgetAccentable()` for system-tinted emphasis, but accept that the color is the user's Lock Screen accent, not ours. Home Screen widgets are the right place for red/green distinction.

### Widget extension needs xcconfig keys in its own Info.plist
The widget extension has its own `Info.plist` — xcconfig values like `AppGroupID`, thresholds, and timing are NOT automatically inherited from the main app. They must be explicitly added to `StatusWidget/Info.plist` with `$(VARIABLE)` references. Missing keys cause silent crashes (widget renders blank).

### Widget deployment target must match the device
Xcode may default a new widget extension target to a higher iOS version than the rest of the project. If the widget doesn't appear in the gallery, check `IPHONEOS_DEPLOYMENT_TARGET` in the widget's build settings.

### Nightscout widgets fetch from inside the timeline provider
Unlike `ShieldConfig` / `ShieldAction` / `DeviceActivityMonitor`, **WidgetKit extensions DO have network access** — the no-network rule above applies only to Screen Time extensions. We use that to keep widgets fresh when `BGAppRefreshTask` doesn't fire: `WidgetNightscoutRefresh.refreshIfDue(...)` is called from every `getTimeline` / `snapshot` on the iPhone `StatusWidget` and writes glucose/carbs back to the App Group with "save if newer" semantics. Guards: skipped when Nightscout is disabled or mock mode is on, throttled to one fetch per `nightscoutLastFetchedAt + 60s` so snapshot/placeholder/timeline calls coalesce, and bounded by a 5s per-request timeout so a flaky server can't burn the timeline budget. iOS-imposed limits that remain: WidgetKit timeline calls have a budget of ~30s end-to-end, and iOS still decides when to ask us for a fresh timeline (we hint with `.atEnd` plus several entries spaced 1 minute apart, but the system can defer reloads when the device is in low-power mode or our refresh budget is exhausted).

### `BGTaskScheduler.submit` replaces same-identifier requests
Submitting a new `BGAppRefreshTaskRequest` with an identifier that already has a pending request replaces it — it does not stack. That's why `NightscoutManager.fetchAll()` can call `scheduleBackgroundRefresh()` at the end of every fetch (foreground poll, BG wake, scene transition) without piling up requests: there's always exactly one pending request, with the most recent `earliestBeginDate`.

## HealthKit

### Glucose unit conversion
HealthKit stores blood glucose in mg/dL internally. Convert to mmol/L (÷ 18.018) before writing to the App Group — mmol/L is standard in the Netherlands.

### Background delivery
`HKObserverQuery` with `enableBackgroundDelivery(for:frequency:.immediate)` wakes the app when new samples arrive. More reliable than `BGAppRefreshTask`.

## App Store / fastlane

### Fastlane deliver ignores device-size subfolders
`deliver`'s screenshot loader (`deliver/lib/deliver/loader.rb`) globs PNGs **flat** from each locale folder:

```ruby
Dir.glob(File.join(path, "*.#{extensions}"))
```

No recursion. If the PNGs live in `iOS/fastlane/screenshots/<locale>/iPhone-6.9/` (or any other subdir), deliver sees zero files, uploads zero, and still exits green — the push reports "Successfully uploaded all screenshots" in ~2 seconds while App Store Connect ends up with an empty deck. Diagnosed on 2026-04-25 with fastlane 2.232.2 (issue #95).

The fix is the layout itself: keep PNGs directly under `<locale>/` — `capture.sh`, `sync-screenshots.sh`, and the `Deliverfile` comment all reflect this. If a future agent is tempted to re-introduce a device-size subdir ("so the Watch shots don't collide with iPhone"), don't — deliver derives the device tier from the PNG **pixel dimensions** (1320×2868 → `APP_IPHONE_67` in `deliver/lib/deliver/app_screenshot.rb`, which ASC accepts for 6.9" devices too). Mixing iPhone + Watch + iPad in the same locale folder is fine; deliver buckets them by resolution, not by filename or subdir.

## Naming

### Bundle identifiers kept as nl.fokkezb.*
Bundle identifiers, App Group ID, and bundle prefix all live in `Config.xcconfig`. If you fork, change these there and re-do Signing & Capabilities for all 5 targets.

### MainApp struct
The `@main` app struct is `MainApp` in `App/App.swift`. If Xcode can't find the entry point after renaming, check the file and struct names match.
