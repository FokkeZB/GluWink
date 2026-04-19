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

### Family Controls Distribution entitlement is self-serve, but App Store Review still gates it
The `com.apple.developer.family-controls` entitlement is one of Apple's "restricted capabilities". Apple grants the **Development** variant automatically to any team, so dev builds and Run-on-device work out of the box. The **Distribution** variant — needed for any App Store / TestFlight build — is requested per team at https://developer.apple.com/contact/request/family-controls-distribution/.

As of 2026-04 the form is **self-serve attestation**, not a manual review. You enter name, email, team ID, accept the Apple Developer License Agreement, and tick that GluWink's primary purpose is one of:

1. parental supervision of children's app usage via Family Sharing, or
2. an individual managing their own device for focus, productivity, or personal device-usage management.

GluWink fits both (parent-managing-child + adult-self-managing diabetes check-in). Click *Get Entitlement* and the capability is attached to the team within minutes — no human gatekeeper at this step. The Apple Developer License Agreement clauses on the form make the limits explicit: no ad blocking, no organisational/MDM use, no managing another adult's device, no sharing the data received through the framework with advertisers or data brokers.

The real evaluation moves to **App Store Review** (guideline 5.5) when you submit a build. If the shipped app doesn't match the attested purpose, Apple rejects there. Spell the medical use case out in App Review notes (see `AppStore/README.md` → Production checklist).

Symptom when the entitlement isn't attached to the team yet (or hasn't propagated to the auto-generated Distribution profile): `xcodebuild archive` succeeds, then `xcodebuild -exportArchive` fails with one error per Family-Controls-using target:

```
error: exportArchive Provisioning profile "iOS Team Store Provisioning Profile: nl.fokkezb.GluWink.ShieldConfig" doesn't include the Family Controls (Development) capability.
error: exportArchive Provisioning profile "iOS Team Store Provisioning Profile: nl.fokkezb.GluWink.ShieldConfig" doesn't include the com.apple.developer.family-controls entitlement.
```

The "(Development)" wording is misleading — it means the auto-generated Store profile is *limited to* the Development variant of the entitlement (which is all Apple lets it carry until the Distribution attestation is done), not that the binary asked for a Development entitlement. There is no code workaround: removing the entitlement gates out the entire shielding feature, and ad-hoc / enterprise export can't reach TestFlight. The only path is to complete the form, wait for the Distribution profile to refresh (a re-run of `make appstore-beta` with `-allowProvisioningUpdates` regenerates it), and try again. Targets affected: `App`, `ShieldConfig`, `ShieldAction`, `DeviceActivityMonitor`.

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

## HealthKit

### Glucose unit conversion
HealthKit stores blood glucose in mg/dL internally. Convert to mmol/L (÷ 18.018) before writing to the App Group — mmol/L is standard in the Netherlands.

### Background delivery
`HKObserverQuery` with `enableBackgroundDelivery(for:frequency:.immediate)` wakes the app when new samples arrive. More reliable than `BGAppRefreshTask`.

## Naming

### Bundle identifiers kept as nl.fokkezb.*
Bundle identifiers, App Group ID, and bundle prefix all live in `Config.xcconfig`. If you fork, change these there and re-do Signing & Capabilities for all 5 targets.

### MainApp struct
The `@main` app struct is `MainApp` in `App/App.swift`. If Xcode can't find the entry point after renaming, check the file and struct names match.
