# Contributing to GluWink

GluWink is an open-source app that shields all apps on a device until the user acknowledges their diabetes status. It's built for parents of children with diabetes — and for adults who want intentional friction on their own device.

The current implementation is iOS only, but ports to other platforms (Android, watchOS, Wear OS, etc.) are very welcome — please open an issue first to discuss the approach so we can align on architecture and shared concepts. The rest of this guide is iOS-specific; a parallel guide can be added when work on another platform begins.

This guide covers how to set up the iOS project, how the codebase is organized, and what to keep in mind when making changes.

## Prerequisites (iOS)

- **macOS** with **Xcode 15+** (Swift 5.9+, iOS 15+ deployment target)
- A **physical iPhone** — Screen Time APIs do not work in the Simulator
- An **Apple Developer account** (free or paid) for code signing
- USB cable to connect your iPhone to your Mac

## Getting Started

### 1. Clone and open

```bash
git clone <repo-url>
cd GluWink
open iOS/App.xcodeproj
```

### 2. Change the bundle identifiers

The project ships with `nl.fokkezb.GluWink` identifiers. You'll need your own. Edit `iOS/Config.xcconfig`:

```
APP_GROUP_ID = group.com.yourname.GluWink
BUNDLE_PREFIX = com.yourname.GluWink
```

Then update Signing & Capabilities in Xcode for **all five targets** — select your team and let Xcode generate provisioning profiles.

### 3. Build and deploy

You can build and install from the terminal without opening Xcode:

```bash
make deploy    # build + install on connected iPhone
make build     # build only
make install   # install last build
```

Or use Xcode's Run button (Cmd+R) with the `App` scheme and your iPhone selected.

### 4. First launch

On the device the app will walk through a setup flow:

1. **Authorize** — grants Screen Time access (requires parent Apple ID for children, or self-auth for adults)
2. **Select excluded apps** — pick which apps should NOT be shielded (e.g. the CGM app)
3. **Set a passphrase** — gates access to settings later

## Project Structure

```
GluWink/
├── iOS/
│   ├── Config.xcconfig              # Bundle IDs, thresholds, timing — single source of truth
│   ├── App.xcodeproj                # Xcode project (5 targets)
│   ├── App/                         # Main app target
│   │   ├── App.swift                # @main entry point
│   │   ├── ContentView.swift        # Routes to SetupView or ShieldingActiveView
│   │   ├── SetupView.swift          # One-time setup flow
│   │   ├── ShieldingActiveView.swift # "Shielding active" screen
│   │   ├── SettingsView.swift       # Passphrase-gated settings
│   │   ├── PassphrasePromptView.swift
│   │   ├── KeychainManager.swift    # Passphrase storage (Keychain)
│   │   ├── SharedDataManager.swift  # App Group UserDefaults wrapper
│   │   ├── ShieldContent.swift      # Shared shield display logic
│   │   ├── ShieldManager.swift      # ManagedSettingsStore wrapper
│   │   ├── ActivityScheduler.swift  # DeviceActivity scheduling
│   │   ├── HealthKitManager.swift   # Glucose + carb fetching
│   │   ├── Constants.swift          # Reads xcconfig values at runtime
│   │   ├── en.lproj/               # English strings
│   │   └── nl.lproj/               # Dutch strings
│   ├── ShieldConfig/                # Shield Configuration Extension
│   ├── ShieldAction/                # Shield Action Extension
│   ├── DeviceActivityMonitor/       # Device Activity Monitor Extension
│   └── StatusWidget/                # WidgetKit Extension
├── Makefile                         # Build, deploy, screenshot commands
├── AGENTS.md                        # Architecture deep-dive (for AI agents and humans)
├── QUIRKS.md                        # Platform quirks and hard-won lessons
└── CONTRIBUTING.md                  # This file
```

### Five targets

| Target | Bundle ID suffix | Purpose |
|--------|-----------------|---------|
| **App** | (base) | Main app — authorization, HealthKit, settings |
| **ShieldConfig** | `.ShieldConfig` | Renders the shield check-in UI |
| **ShieldAction** | `.ShieldAction` | Handles shield button taps |
| **DeviceActivityMonitor** | `.DeviceActivityMonitor` | Re-arms shields on a schedule |
| **StatusWidget** | `.StatusWidget` | Home/Lock Screen widgets |

All targets share an **App Group** for data exchange. The main app writes; extensions read.

### Key files to read first

- **`AGENTS.md`** — full architecture, data flow, constraints, and security model
- **`QUIRKS.md`** — platform quirks and API gotchas (read before making changes)
- **`Config.xcconfig`** — all configurable values in one place

## Coding Conventions

### Swift

- Swift 5.9+, SwiftUI for all UI
- `async/await` for all asynchronous work — no completion handlers
- All shared data access goes through `SharedDataManager` (wraps App Group UserDefaults)
- Extensions must be lightweight — limited memory, no HealthKit, no network
- Use `os.Logger` for logging in extensions (`print()` output may not be visible)
- Prefix unused function parameters with `_`

### App name

Never hardcode "GluWink" in Swift code. Use `Constants.displayName` (reads `CFBundleDisplayName` from xcconfig) and `%@` format specifiers in strings files. The app is designed to be easily renamed — see the "Renaming the App" section in `AGENTS.md`.

### Localization

The app is localized in **English** and **Dutch** from day one.

- All user-facing strings must use `String(localized:)` or `LocalizedStringKey`
- Provide both `en` and `nl` translations when adding new text
- Use descriptive keys: `"shield.checkbox.checkPump"` not `"label1"`
- Shield extension strings live in the `ShieldConfig` bundle, not the main app
- Info.plist strings go in `InfoPlist.strings` per language

### Security model

The child must have zero control over the app's behavior. Do **not** add:

- Settings screens accessible without the passphrase
- Hidden gestures, long-press menus, or debug toggles (except `#if DEBUG` on device)
- URL scheme handlers that modify configuration
- Any bypass mechanism a child could discover

See `AGENTS.md` for the full security design philosophy.

## Testing

### No Simulator for Screen Time

Screen Time APIs (`FamilyControls`, `ManagedSettings`, `DeviceActivity`) only work on a physical device. The Simulator is useful for iterating on UI layout with mock data, but you must test shielding behavior on a real iPhone.

### Mock data (DEBUG builds)

In DEBUG builds on a physical device, open Settings (gear icon) and scroll to the "Mock Data" section. This lets you simulate glucose values, carb entries, and timing without a real CGM — useful for testing shield attention logic.

### What to test on device

- Shield appears on all non-excluded apps
- Shield check-in flow works (checkboxes, dismiss, defer)
- Shields re-arm after the configured interval
- HealthKit data flows through to the shield UI
- Widgets update with current data
- Passphrase gate works correctly
- Localization displays correctly in both languages

## Making Changes

### Before you start

1. Read `QUIRKS.md` to avoid repeating known mistakes
2. Read `AGENTS.md` for architecture details relevant to your change

### Proposing changes

- For bug fixes and small improvements, open a PR directly
- For new features or architectural changes, open an issue first to discuss the approach

### Useful Make commands

```bash
make deploy       # Build and install on connected iPhone
make build        # Build only
make install      # Install last build on device
make screenshot   # Capture iPhone screen (requires tunneld)
make tunneld      # Start USB tunnel daemon (once per session, needs sudo)
```

## License

GluWink is released under the **PolyForm Noncommercial License 1.0.0**
(see [`LICENSE`](./LICENSE)) with a small addendum that reserves public
app-store distribution to the maintainers. In short:

- **You may**: read the code, modify it, contribute back (including ports to
  other platforms such as Android, watchOS, Wear OS, etc.), build it for your
  own devices, and share builds with private testers under your own developer
  account (Apple TestFlight / Ad-Hoc / Enterprise, Google Play closed or
  internal testing tracks, Firebase App Distribution, direct APK sideloading,
  and equivalent mechanisms on other platforms).
- **You may not**: sell the app or any derivative in any form (paid downloads,
  subscriptions, IAPs, paid support sold as a product), or publish the app for
  general public availability — under this name or any other — to the Apple
  App Store, Google Play Store, or any other public marketplace.

By submitting a contribution you agree it may be distributed under the same
terms. See [`LICENSE`](./LICENSE) for the full text. If you'd like to do
something the license does not allow, open an issue — exceptions can be
granted in writing.

## Additional Resources

- **`AGENTS.md`** — deep architecture reference, data flow diagrams, API usage patterns
- **`QUIRKS.md`** — things that don't work the way you'd expect
- **`LICENSE`** — full license text (PolyForm Noncommercial 1.0.0) and the project's additional terms (no-commercial-sale, no public app-store publishing, permitted private tester distribution)
