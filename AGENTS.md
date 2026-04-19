# AGENTS.md — GluWink (Diabetes Shield App)

## Project Overview

**App name:** **GluWink** — use this in user-facing copy, issues, and docs. The repository folder on disk may use a different name (for example `GlucoGuard`); the product and Xcode targets are GluWink.

An iOS app that shields all apps on a device until the user acknowledges their diabetes status. Built on Apple's Screen Time API (iOS 15+). Works for **two audiences**:

- **Children (via Family Sharing):** The parent authorizes the app once via FamilyControls (`.child` member). The child cannot delete the app or change settings.
- **Adults (self-managing):** The user authorizes directly via FamilyControls (`.individual` member). The app adds friction — not absolute prevention — because adults can always delete the app themselves. An "accountability partner" (spouse, friend) ideally sets the passphrase during setup.

The app tries `.child` authorization first. If that fails (no Family Sharing configured), it automatically falls back to `.individual`. The authorization mode is persisted so re-authorization on subsequent launches uses the correct member.

The app is open source, localized in English and Dutch, and designed so other parents of children with diabetes — or adults managing their own — can build and use it.

## Agent configuration conventions

This repo is worked on from multiple AI agents (Cursor, Claude Code, etc.). When adding configuration files, prefer **agent-agnostic formats first** so all tools benefit:

| Purpose | Preferred (agent-agnostic) | Fallback (Claude-specific, picked up by Cursor) | Avoid |
|---------|---------------------------|--------------------------------------------------|-------|
| Agent instructions | `AGENTS.md` (repo root) | `.claude/AGENTS.md` (also read by Cursor) | `.cursorrules`, `.cursor/rules/` exclusively |
| MCP servers | `.mcp.json` (repo root) | — | `.cursor/mcp.json` exclusively |
| Skills / tools | `.claude/skills/` | — | `.cursor/skills/` exclusively |

**Rationale:** `.mcp.json` at the repo root is read by both Claude Code and Cursor. `AGENTS.md` is read by Claude Code natively and by Cursor via its rules system. Agent-specific config directories (`.cursor/`, `.claude/`) should only be used when there is no shared equivalent, or when behavior genuinely differs between agents.

## Xcode MCP Server

The project includes an MCP server (`.mcp.json`) that connects to a running Xcode instance via `xcrun mcpbridge`. **Xcode must be open** for the server to work. When available, prefer MCP tools over shell-based alternatives:

| Task | Use (MCP) | Instead of |
|------|-----------|------------|
| Build the project | `BuildProject` | `make build` / `xcodebuild` |
| Check build errors | `GetBuildLog`, `XcodeListNavigatorIssues` | Parsing `xcodebuild` output |
| File diagnostics | `XcodeRefreshCodeIssuesInFile` | `ReadLints` (for Swift files) |
| Add new Swift files | `XcodeWrite` (auto-adds to project) | `Write` + manual `.pbxproj` edit |
| Search Apple docs | `DocumentationSearch` | Web search |
| Preview SwiftUI views | `RenderPreview` | Deploy + screenshot |
| Run tests | `RunAllTests` / `RunSomeTests` | — |
| Quick runtime check | `ExecuteSnippet` | Writing a test |

**Not covered by MCP (use skills/Makefile instead):**
- **Deploy to device:** `make install` — MCP has no device install tool.
- **Device screenshot:** `ios-screenshot` skill — `RenderPreview` only renders previews, not the real device screen.

**All MCP tools require a `tabIdentifier`.** Call `XcodeListWindows` first to get it.

## Quirks & Gotchas

**`QUIRKS.md`** (repo root) documents platform quirks, API limitations, Xcode build gotchas, and other hard-won lessons. Read it before making changes to avoid repeating mistakes.

## Always think automation

If you find yourself running a multi-step manual workflow that the user is likely to ask for again — site audits, screenshot capture, App Store sync, release prep, anything that takes more than two commands and some judgement — **propose extracting it before you finish the current task**. Don't wait to be asked. The cost is one short conversation; the reward is that "audit the site" / "ship a beta" / "regenerate screenshots" becomes a single sentence forever after.

The pattern this repo uses:

| Layer | Lives in | Owns |
|---|---|---|
| Mechanical work | A `make <target>` in the repo `Makefile`, optionally backed by a script under `<surface>/scripts/` (e.g. `docs/scripts/lighthouse-audit.sh`) | The deterministic part — build, run, parse, print. Idempotent, exits 0 on success. |
| Reasoning / orchestration | A `.claude/skills/<name>/SKILL.md` with a `description:` that lists the natural-language triggers | When to run, how to interpret the output, what to do next (file an issue, propose a fix, stop and report). |
| Trigger | Any natural phrasing the user is likely to use | The skill's `description` is what the agent matches on, so include the obvious synonyms. |

**Worked example — site audits.** After running Lighthouse manually, filing issue #56 by hand, and writing a fix PR for it on 2026-04-19, the same workflow was extracted into:

- `make docs-audit` → `docs/scripts/lighthouse-audit.sh` (builds, serves, runs Lighthouse on `/` and `/nl/`, prints summary + failing audits)
- `.claude/skills/site-audit/SKILL.md` (triggered by "audit the site", "lighthouse the site", etc. — runs the make target, decides whether action is needed, proposes to file an issue and implement fixes following the structure of #56)

So now "audit the site" is a one-liner instead of ~15 minutes of judgement calls. **When you ship the next thing that smells like this, do the same**: ship the make target, ship the skill, mention both in the PR description, and add a one-line worked-example pointer here so future agents see the pattern.

## Device Prerequisites (manual, not part of the app)

### For children (parent-managed)

Before installing GluWink on the child's iPhone:

1. **Family Sharing** must be set up with the parent as organizer and the child as a member.
2. **Manage Screen Time from the parent's device, NOT locally on the child's device.** On the parent's iPhone: Settings → Family → [child] → Screen Time. This way the child's restrictions are tied to the parent's Apple ID — there is no Screen Time passcode on the child's device to guess or brute-force. Changes require the parent's Apple ID authentication.
3. **Disable app deletion** (from the parent's device): Content & Privacy Restrictions → iTunes & App Store Purchases → Deleting Apps → **Don't Allow**.
4. **Disable "Install Apps"** (from the parent's device): same location → Installing Apps → **Don't Allow**. This prevents the child from installing Screen Time workaround tools or anything else without parent approval.
5. **CGM app must write to Apple Health.** Verify that the child's diabetes app (Dexcom, Libre, CamAPS, etc.) is configured to share glucose readings and carb entries with Apple Health. Check in: Settings → Health → Data Access & Devices → [CGM app].

**Do NOT set a local Screen Time passcode on the child's device.** That's a 4-digit code the child will eventually figure out. The Family Sharing approach has no code — it's gated by the parent's Apple ID.

### For adults (self-managing)

1. **CGM app must write to Apple Health** (same as above).
2. **No Family Sharing needed.** The app authorizes with `.individual` which doesn't require a parent account.
3. **Have an accountability partner set the passphrase** during initial setup. The partner should be someone who will hold you accountable (spouse, friend, sibling). Without this, you can always open settings yourself — the passphrase only adds friction.
4. **The adult can always delete the app.** Unlike the child setup, there is no way to prevent this. The value proposition for adults is intentional friction, not absolute enforcement. This should be clearly communicated in the App Store listing, README, and marketing site.

These are iOS system settings, not things the app can enforce programmatically.

## Security Design Philosophy

**The child must have zero control over the app's behavior.** The app has two states:

1. **Not set up yet** → shows the setup flow (authorize → pick excluded apps → set passphrase).
2. **Set up** → shows a "shielding active" screen with a gear icon for settings.

Settings are gated by a **passphrase** stored in the device Keychain (SHA-256 hashed with a random salt). The passphrase is set during initial setup — for children, the parent sets it (they're present for Apple ID auth); for adults, ideally an accountability partner sets it.

If the passphrase is forgotten: delete and reinstall the app (requires the parent's Apple ID for child devices, or just the user for adult devices).

**Settings exposed behind the passphrase:**
- Excluded apps (FamilyActivityPicker)
- Glucose thresholds (high/low mmol/L)
- Glucose stale minutes
- Carb grace period (hour/minute)
- Glucose badge (off / always / only when attention needed)
- Passphrase change

**Shields are NEVER removed during the settings flow.** Opening settings does not temporarily disable shielding.

**Do NOT add** any of the following, even if it seems convenient:
- Long-press or multi-tap gestures to access admin features
- Debug menus (debug mock controls are `#if DEBUG` only, bottom-trailing, with a ladybug icon)
- URL scheme handlers that modify configuration
- Any mechanism a child could discover or brute-force to bypass the passphrase

## Architecture

### Targets

The Xcode project has **seven targets**:

1. **App (main app)** — `nl.fokkezb.GluWink`. SwiftUI app. Handles FamilyControls authorization, one-time app selection, background glucose data fetching, and WatchConnectivity settings sync to the watch.
2. **ShieldConfig** — `nl.fokkezb.GluWink.ShieldConfig`. Shield Configuration Extension. Provides the custom shield UI (the check-in screen the child sees). Runs in a sandboxed process.
3. **ShieldAction** — `nl.fokkezb.GluWink.ShieldAction`. Shield Action Extension. Handles the child's interaction with the shield (checkbox taps, dismiss). Runs in a sandboxed process.
4. **DeviceActivityMonitor** — `nl.fokkezb.GluWink.DeviceActivityMonitor`. Device Activity Monitor Extension. Re-arms shields on device activity events (interval start). Runs in the background.
5. **StatusWidget** — `nl.fokkezb.GluWink.StatusWidget`. WidgetKit Extension. Home Screen (small/medium/large), Lock Screen (circular/rectangular/inline), and StandBy widgets showing glucose + carb status with red/green attention tint.
6. **WatchApp** — `$(WATCH_BUNDLE_ID)`. watchOS SwiftUI app. Reads HealthKit directly on the Watch, stores a watch-local snapshot in the shared App Group, and renders the compact watch UI.
7. **WatchWidget** — `$(WATCH_WIDGET_BUNDLE_ID)`. watchOS WidgetKit extension for Apple Watch complications. Reads the watch-local App Group snapshot and supports configurable single-metric complications plus a combined rectangular complication.

Shared code and shield-localized strings live in the local Swift package **`SharedKit`** (`iOS/SharedKit`). `App`, `ShieldConfig`, `StatusWidget`, `WatchApp`, and `WatchWidget` all import it.

The iPhone targets share an **App Group** (`group.nl.fokkezb.GluWink`) for data exchange. The Watch app and Watch widget also use the same App Group identifier on the watch device, but that storage is **device-local** — the phone and watch do not share one physical container.

### Shared App Group Container

On iPhone, the main app writes data here and the extensions read it. On watchOS, the Watch app writes its own HealthKit snapshot and synced settings here, and the Watch widget reads them. Use `UserDefaults(suiteName: "group.nl.fokkezb.GluWink")`.

Stored keys:

| Key | Type | Written by | Read by |
|-----|------|-----------|---------|
| `currentGlucose` | Double (mmol/L) | Main app (HealthKit) or Watch app (HealthKit) | ShieldConfig, WatchWidget |
| `glucoseFetchedAt` | Date (ISO 8601) | Main app (HealthKit) or Watch app (HealthKit) | ShieldConfig, WatchWidget |
| `lastCarbEntryGrams` | Double | Main app (HealthKit) or Watch app (HealthKit) | ShieldConfig, WatchWidget |
| `lastCarbEntryAt` | Date (ISO 8601) | Main app (HealthKit) or Watch app (HealthKit) | ShieldConfig, WatchWidget |
| `attentionDeferredAt` | Date (ISO 8601) or absent | ShieldAction | ShieldConfig |
| `shieldDismissedAt` | Date (ISO 8601) | ShieldAction | DeviceActivityMonitor |
| `allowedAppTokens` | Data (encoded `Set<ApplicationToken>`) | Main app (FamilyActivityPicker) | Main app (ManagedSettingsStore) |
| `checkInIntervalMinutes` | Int | Main app (hard-coded, default 30) | DeviceActivityMonitor |
| `authorizationMember` | String ("child" or "individual") | Main app (setup) | Main app (re-auth on launch) |
| `highGlucoseThreshold` | Double (mmol/L) or absent | Main app (settings / WatchConnectivity sync) | ShieldConfig, ShieldAction, WatchApp, WatchWidget |
| `lowGlucoseThreshold` | Double (mmol/L) or absent | Main app (settings / WatchConnectivity sync) | ShieldConfig, ShieldAction, WatchApp, WatchWidget |
| `glucoseStaleMinutes` | Int or absent | Main app (settings / WatchConnectivity sync) | ShieldConfig, WatchApp, WatchWidget |
| `carbGraceHour` | Int or absent | Main app (settings / WatchConnectivity sync) | ShieldConfig, WatchApp, WatchWidget |
| `carbGraceMinute` | Int or absent | Main app (settings / WatchConnectivity sync) | ShieldConfig, WatchApp, WatchWidget |
| `glucoseUnit` | String ("mmolL" or "mgdL") or absent | Main app (settings / HealthKit auto-detect / WatchConnectivity sync) | ShieldConfig, StatusWidget, Main app, WatchApp, WatchWidget |
| `glucoseBadgeMode` | String ("off", "always", "onlyWhenAttention") or absent | Main app (settings) | Main app (badge update) |

> **Settings override precedence:** Extensions read settings keys from App Group first; if absent (never changed), they fall back to `Info.plist` values (from xcconfig). The passphrase itself is NOT in the App Group — it's in the device Keychain.

> **Note:** HealthKit stores glucose in mg/dL internally. Convert to mmol/L (÷ 18.018) before writing to the App Group, since that's what's used in the Netherlands.

### Data Flow

```
[CGM App / Libre / Dexcom] --writes--> [Apple HealthKit on iPhone]
                                              |
                                    (HKObserverQuery with
                                     background delivery)
                                              |
                                              v
                                     [Main App reads HK]
                                              |
                                              v
                             [iPhone App Group UserDefaults]
                                              |
                    +-------------------------+-------------------------+
                    |                         |                         |
                    v                         v                         v
          [ShieldConfig extension]   [StatusWidget extension]  [DeviceActivityMonitor]
           reads glucose + carbs      reads glucose + carbs     re-arms shields after
           renders check-in UI        renders widgets           interval expires
                    |
                    v
          [ShieldAction extension]
           validates check-in
           writes shieldDismissedAt
           removes shields temporarily

[Apple HealthKit on Watch] --> [WatchApp reads HK] --> [Watch App Group UserDefaults] --> [WatchWidget]
                                         ^
                                         |
                           [WatchConnectivity settings sync from iPhone]
```

**Why HealthKit instead of a CGM API?** The child's CGM app (Dexcom, Libre, etc.) already writes glucose readings and carb entries to Apple Health. Reading locally via HealthKit avoids external API auth, network dependencies, and background fetch throttling. HealthKit's `HKObserverQuery` with background delivery wakes the app when new samples arrive — much more reliable than `BGAppRefreshTask`.

## Key Technical Constraints

### Things that WILL NOT work (do not attempt)

- **No network requests from extensions.** ShieldConfig extension, ShieldAction extension, and DeviceActivityMonitor extension cannot make HTTP calls. All external data must be pre-fetched by the main app and stored in the App Group.
- **No HealthKit from extensions.** Extensions cannot query HealthKit directly. The main app reads HealthKit and writes results to the App Group.
- **No bundle ID-based app identification.** The Screen Time API uses opaque `ApplicationToken` values. You cannot look up or hard-code an app by its bundle ID. Allowed apps must be selected once via `FamilyActivityPicker`.
- **No simulator testing.** Screen Time APIs only work on physical devices.
- **No ad-hoc distribution.** The app must be run via Xcode directly on the device, or distributed through TestFlight.
- **Extensions have very limited memory.** Keep shield UI simple. No heavy images, no complex view hierarchies. SwiftUI is fine but keep it lean.
- **Extensions cannot present alerts or sheets.** The shield UI is the only UI surface you get.
- **`ManagedSettingsStore` changes are not instant.** There can be a slight delay when applying or removing shields.

### Things that DO work

- Extensions CAN read from the shared App Group (UserDefaults and files).
- Extensions CAN write to the shared App Group.
- The main app CAN use HealthKit `HKObserverQuery` with background delivery to wake up when new glucose/carb data arrives.
- `DeviceActivityMonitor` CAN call into `ManagedSettingsStore` to re-apply shields.
- You CAN customize the shield appearance via `ShieldConfig extension`.

## Screen Time API Usage

### Authorization (main app, one-time)

```swift
import FamilyControls

// Try .child first (requires parent Apple ID via Family Sharing).
// If that fails (no Family Sharing), fall back to .individual (self-auth for adults).
do {
    try await AuthorizationCenter.shared.requestAuthorization(for: .child)
    SharedDataManager.shared.authorizationMember = .child
} catch {
    try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
    SharedDataManager.shared.authorizationMember = .individual
}
```

### Selecting Allowed Apps

Use `FamilyActivityPicker` to let the parent (or adult user) choose which apps are NOT shielded (diabetes apps). Persist the resulting `FamilyActivitySelection` to the App Group.

**Setup flow:** authorization → app selection → passphrase creation → save & activate. The setup flow only appears when no persisted tokens exist. The main app checks on launch:
- If `allowedAppTokens` exists in App Group → go straight to the "shielding active" state with settings gear.
- If `allowedAppTokens` is missing → show the setup flow.

**To reconfigure after setup:** tap the gear icon on the shielding active screen → enter the passphrase → change settings. Shields remain active during the entire settings flow.

```swift
import FamilyControls

@State var selection = FamilyActivitySelection()

// In the one-time parent setup view:
FamilyActivityPicker(selection: $selection)

// After selection, encode and store:
let data = try JSONEncoder().encode(selection)
UserDefaults(suiteName: "group.nl.fokkezb.GluWink")?.set(data, forKey: "allowedAppTokens")
```

### Applying Shields (main app + DeviceActivityMonitor)

```swift
import ManagedSettings

let store = ManagedSettingsStore()

// Shield ALL apps and categories
store.shield.applications = nil  // nil = not filtering (wrong!)
// Correct: shield everything, then exclude allowed apps
store.shield.applicationCategories = .all(except: allowedCategories)

// OR: use DeviceActivityCenter to schedule monitoring,
// then apply shields from the DeviceActivityMonitor extension
```

> **Important:** The exact incantation for "shield everything except X" can be tricky. The `ShieldSettings` API uses `applicationCategories` with `.all(except:)`. Refer to Apple's documentation if the compiler complains — the API surface has changed across iOS versions.

### Shield Configuration Extension

Subclass `ShieldConfigurationDataSource`. This is where the check-in UI is defined. Read glucose data from the App Group and return a `ShieldConfiguration` with label, subtitle, and button text.

**Note:** This extension provides *configuration* (text/appearance), not interactive UI. Interactive behavior is handled by `ShieldAction extension`.

### Shield Action Extension

Subclass `ShieldActionDelegate`. Handle `.primaryButtonPressed` and `.secondaryButtonPressed`. On successful check-in:

1. Write `shieldDismissedAt = Date()` to App Group.
2. Remove shields by clearing `ManagedSettingsStore().shield`.
3. The DeviceActivityMonitor will re-arm shields after the configured interval.

### Device Activity Monitor Extension

Subclass `DeviceActivityMonitor`. Override `intervalDidStart(for:)` and `intervalDidEnd(for:)`.

Use `DeviceActivityCenter` from the main app to schedule a recurring monitoring interval. When the interval fires, the extension checks `shieldDismissedAt` — if enough time has passed (> `checkInIntervalMinutes`), re-apply shields.

## HealthKit Integration (Main App Only)

The main app reads glucose and carbohydrate data from Apple HealthKit. Extensions CANNOT access HealthKit — the main app reads it and writes to the App Group.

### HealthKit Authorization

Request read access on first launch for two sample types:

```swift
import HealthKit

let healthStore = HKHealthStore()
let glucoseType = HKQuantityType(.bloodGlucose)
let carbType = HKQuantityType(.dietaryCarbohydrates)

try await healthStore.requestAuthorization(toShare: [], read: [glucoseType, carbType])
```

The child must approve HealthKit access on their device. Add the `HealthKit` capability to the main app target in Xcode and add `NSHealthShareUsageDescription` to Info.plist.

### Background Delivery via HKObserverQuery

Register observer queries so the app wakes up when new glucose or carb samples are written (by the CGM app or pump app):

```swift
// Enable background delivery for both types
try await healthStore.enableBackgroundDelivery(for: glucoseType, frequency: .immediate)
try await healthStore.enableBackgroundDelivery(for: carbType, frequency: .immediate)

// Set up observer queries (in app init or didFinishLaunching)
let glucoseObserver = HKObserverQuery(sampleType: glucoseType, predicate: nil) { query, completionHandler, error in
    Task {
        await self.fetchLatestGlucose()
        completionHandler()
    }
}
healthStore.execute(glucoseObserver)
```

### Fetching Latest Values

```swift
func fetchLatestGlucose() async {
    let glucoseType = HKQuantityType(.bloodGlucose)
    let sortDescriptor = SortDescriptor(\HKQuantitySample.startDate, order: .reverse)
    let descriptor = HKSampleQueryDescriptor(
        predicates: [.quantitySample(type: glucoseType)],
        sortDescriptors: [sortDescriptor],
        limit: 1
    )
    
    if let sample = try? await descriptor.result(for: healthStore).first {
        let mgdl = sample.quantity.doubleValue(for: .gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci)))
        let mmol = mgdl / 18.018
        
        let defaults = UserDefaults(suiteName: "group.nl.fokkezb.GluWink")
        defaults?.set(mmol, forKey: "currentGlucose")
        defaults?.set(sample.startDate.ISO8601Format(), forKey: "glucoseFetchedAt")
    }
}
```

Use the same pattern for carbs with `HKQuantityType(.dietaryCarbohydrates)`, writing `lastCarbEntryGrams` and `lastCarbEntryAt` to the App Group.

### Prerequisite

The child's CGM app (Dexcom, Libre, CamAPS, etc.) must be configured to write glucose data to Apple Health. Most do this by default, but verify in the CGM app's settings.

## Check-In Rules (Hard-Coded)

The shield check-in logic lives in the ShieldAction extension. Rules determine what the child must acknowledge before the shield can be dismissed.

> **TODO:** Finalize rules. Draft rules below as a starting point:

```
ALWAYS required:
- [ ] "I have checked my pump"

IF currentGlucose > 14.0 mmol/L:
- [ ] "My glucose is high. I have taken corrective action."
- Shield CANNOT be dismissed (child must manage glucose first)
  → OR: shield CAN be dismissed but re-arms after 10 minutes instead of 30

IF currentGlucose < 4.0 mmol/L:
- [ ] "My glucose is low. I am treating it now."
- Shield CANNOT be dismissed (child must treat low first)
  → OR: shield CAN be dismissed but re-arms after 10 minutes instead of 30

IF no carb entry in last 4 hours AND currentGlucose is in range:
- [ ] "I have entered my recent carbs"

IF glucoseFetchedAt is older than 30 minutes:
- [ ] "My CGM data is stale. I have checked my sensor."
```

**Important:** Because ShieldAction extension has no network or HealthKit access, all data it needs must already be in the App Group. The rules engine reads ONLY from UserDefaults.

## Development Phases

> **Localization from day one:** Use `String(localized:)` for ALL user-facing strings starting in Phase 1. Do not hard-code English or Dutch strings in views. Provide both `en` and `nl` translations as you go. Retrofitting localization later is painful.

### Phase 1: Skeleton + Authorization
- Create all four targets in Xcode with correct entitlements
- Set up App Group
- Implement FamilyControls authorization flow
- Implement FamilyActivityPicker for allowed apps
- Test: app launches, parent can authorize and select diabetes apps

### Phase 2: Basic Shielding
- Apply shields to all apps except selected ones
- Implement ShieldConfig extension with static check-in text
- Implement ShieldAction extension that dismisses shield on button tap
- Test: all apps are shielded, tapping "Done" on shield dismisses it

### Phase 3: Device Activity Monitor
- Schedule recurring DeviceActivity monitoring
- Re-arm shields after configured interval
- Test: shields come back after 30 minutes

### Phase 4: HealthKit Integration
- Add HealthKit capability to main app target
- Request HealthKit read authorization for blood glucose and dietary carbohydrates
- Implement HKObserverQuery with background delivery for both types
- Fetch latest glucose and carb data, write to App Group
- Update ShieldConfig extension to show current glucose and carb status
- Update ShieldAction extension to apply conditional rules
- Test: shield shows current glucose, rules are enforced

### Phase 5: Polish

- **ShieldingActiveView status**: Show last glucose/carb values and fetch time so the parent can verify data is flowing.
- **HealthKit denied warning**: If the child denies HealthKit access, surface a warning on the active screen (currently silently continues with no data).
- **No carb data ever**: If carbs have never been logged (not just 4+ hours ago), the shield shows "No carb data available" but no attention items. Consider treating this as needing attention too.
- **Shield title randomness**: `randomElement()` means the title changes each time the shield renders (including after defer). Could feel jarring — consider pinning per session.
- Ensure all user-facing strings use String(localized:) with English and Dutch translations
- TestFlight distribution

### Phase 5b: In-App Settings (Passphrase-Gated) ✅

**Implemented (2026-04-13).** Settings are accessible via a gear icon on the shielding active screen, gated by a passphrase set during initial setup. Passphrase is stored in the device Keychain (SHA-256 + random salt). Shields are never removed during the settings flow.

**Files:**
- `KeychainManager.swift` — Keychain read/write/verify for passphrase
- `SetupView.swift` — setup flow now includes passphrase creation step
- `PassphrasePromptView.swift` — unlock gate before settings
- `SettingsView.swift` — excluded apps, thresholds, stale minutes, carb grace, passphrase change
- `SharedDataManager.swift` — settings persistence in App Group (overrides xcconfig defaults)

Also implemented: `.individual` authorization fallback for adults without Family Sharing. Authorization mode persisted in App Group as `authorizationMember`.

### Phase 6: Open Source
- Add README.md with setup instructions for other developers
- Add LICENSE file
- Extract hard-coded thresholds and timing values into a single `Rules.swift` config struct
- Document how to change bundle identifiers and App Group
- Create GitHub repository

## App Icon Variants

The iOS App ships **four icon variants** in `iOS/App/Assets.xcassets/`:

| Asset | Type | Purpose |
|-------|------|---------|
| `AppIcon` | `.appiconset` | The home-screen / Settings / Spotlight icon. **Always shown.** Never swapped at runtime. |
| `AppIcon-Blue` | `.imageset` | "No data yet" variant used by **in-app surfaces only** (e.g. `HomeView`'s status header before HealthKit has delivered). Matches the home-screen `AppIcon` artwork. Not shipped to the shield extension — see rule 2 below. |
| `AppIcon-Green` | `.imageset` | "All clear" variant for surfaces we render ourselves. |
| `AppIcon-Red` | `.imageset` | "Needs attention" variant for surfaces we render ourselves. |

The Watch target follows the same convention in `iOS/WatchApp/Assets.xcassets/`.

**Rule:** Green and red may only be shown when we have real glucose or carb data to base the decision on (see `ShieldContent.hasNoData`). Before the first sample arrives, in-app surfaces fall back to the blue variant. The shield UI never reaches the no-data state because shielding can only be enabled once a data source is configured (see `ShieldManager.disableIfNoDataSource()`).

### Rules

1. **Do NOT call `UIApplication.shared.setAlternateIconName(...)`.** We deliberately do not provide alternate `.appiconset`s and do not swap the home-screen icon — it's unreliable, racy with extensions, and confuses users. The home-screen signal is the badge (see `SharedDataManager.refreshAttentionBadge()`).
2. **Use `AppIcon-Blue` / `AppIcon-Red` / `AppIcon-Green` for any surface where we control the rendering at attention-evaluation time.** Selection logic depends on the surface:
   - **In-app surfaces** (e.g. `HomeView`): `hasNoData` → blue; else `needsAttention` → red; else green.
   - **Shield UI** (`ShieldConfigurationExtension`): only red / green. Shielding is gated on having a data source, so `hasNoData` cannot occur; if the configured source has stopped delivering, that's a `needsAttention` case (red).
   - Other examples that follow the in-app rule: future notification attachments / rich content, future widgets that want to show the brand mark with attention state.
3. **In SwiftUI inside the App target:** `Image("AppIcon-Blue")` / `Image("AppIcon-Red")` / `Image("AppIcon-Green")` works because all three are `.imageset`s in the App's asset catalog.
4. **In the ShieldConfig extension** (and any other extension that needs the variants): the App's asset catalog is **not** in the extension's bundle. Each extension that needs the artwork must ship its own copies. ShieldConfig keeps `iOS/ShieldConfig/AppIcon-Red.png` and `iOS/ShieldConfig/AppIcon-Green.png` as raw bundle resources and loads them with `UIImage(contentsOfFile: Bundle.main.path(forResource: "AppIcon-Red", ofType: "png"))`. There is intentionally no blue PNG in the extension. When adding the variants to a new extension, copy the PNGs into that target's folder; this project uses file-system synchronized groups so Xcode will pick them up automatically.
5. **Keep the artworks in sync.** When the icon is redesigned, update: `AppIcon.appiconset`, `AppIcon-Blue.imageset`, `AppIcon-Red.imageset`, `AppIcon-Green.imageset` (in both the App and Watch catalogs where they exist), and the raw PNG copies inside any extension folder. The `icons/` folder at the repo root holds the master SVGs (`iOS.svg`, `iOS-green.svg`, `iOS-red.svg`, and their `watchOS.svg` counterparts; the blue `.imageset`s reuse `iOS.png` / `watchOS.png`).

## Coding Conventions

- Swift 5.9+, SwiftUI for all UI
- Async/await for all asynchronous work (no completion handlers)
- Minimal third-party dependencies (prefer Foundation/URLSession for networking)
- All shared data access goes through a single `SharedDataManager` class that wraps App Group UserDefaults
- Extensions must be kept as lightweight as possible
- Use `os.Logger` for debug logging in extensions (print() may not be visible)
- **Never hardcode the app name in reusable/internal identifiers.** The app may be renamed. Use `Constants.displayName` (reads `CFBundleDisplayName` from xcconfig) in Swift code and `%@` format specifiers in `Localizable.strings` for user-facing copy. Keep reusable/internal folder names, package names, module names, file names, Swift types, and non-user-facing symbols generic (for example `SharedKit`, `StatusWidget`, `CompanionWatchApp`) rather than product-branded. The only exceptions are `InfoPlist.strings` (iOS limitation), bundle identifiers, and last-resort user-facing fallback strings.

## Localization

The app is localized in **English (en)** and **Dutch (nl)**. English is the base/development language.

- **All user-facing strings must use `String(localized:)`** (or `LocalizedStringKey` in SwiftUI views). Never hard-code user-facing text.
- String catalogs (`.xcstrings`) or `.strings` files live in `en.lproj/` and `nl.lproj/`.
- Info.plist strings (permission dialogs) go in `InfoPlist.strings` per language.
- Shield extension UI strings must also be localized — the shield is the primary UI the child sees.
- Keep string keys descriptive: `"shield.checkbox.checkPump"` not `"label1"`.

When adding new user-facing text, always provide both English and Dutch translations.

## Marketing Copy (keep in sync)

The app's marketing message lives in **three surfaces** that must stay aligned. When the user asks for a change to the tagline, promo text, description, or any positioning copy in any one of them, propagate the same change to the others (translated as needed) so messaging never drifts:

| Surface | Files | What lives there |
|---------|-------|------------------|
| In-app home (welcome panel) | `iOS/App/en.lproj/Localizable.strings`, `iOS/App/nl.lproj/Localizable.strings` (`home.welcome.tagline %@`) | One-sentence tagline shown on first launch / empty state |
| App Store listing | `AppStore/en-US.md`, `AppStore/nl-NL.md` | Subtitle, keywords, **promotional text** (170-char), **description** (4000-char) |
| Marketing site | *(future — likely under `Site/` or `docs/` once the GitHub Pages site exists)* | Hero copy, features section, FAQ — should mirror the App Store description |

**Workflow when copy changes:**

1. Apply the user's requested change in the file they referenced.
2. Search the other surfaces for the same phrasing (`Grep` for the old text in EN and NL) and update each match — both languages.
3. If a surface uses a slightly different phrasing or length budget (e.g. App Store promo text is capped at 170 chars), adapt while preserving the same meaning and key terms.
4. After editing App Store copy, recount and update the `*(N / max)*` annotation under each block.
5. Mention which surfaces you touched in your reply so the user can verify.

### Pushing App Store copy to App Store Connect

The `AppStore/<locale>.md` files are the editorial source of truth. To push them to App Store Connect, run `make appstore-push` — it regenerates `iOS/fastlane/metadata/` from the Markdown, then runs `fastlane deliver`.

| Command | When to run |
|---|---|
| `make appstore-sync` | After editing `AppStore/<locale>.md` — fast, no network, validates length limits. |
| `make appstore-push` | When you actually want App Store Connect updated. Updates the editable version; does not submit. |
| `make appstore-pull` | To inspect what App Store Connect currently has (snapshot only — never copy back into the Markdown). |

Setup (one-time) and field mapping live in **`AppStore/README.md` → "Pushing to App Store Connect (fastlane)"**. Auth is via an API key JSON at `private/asc-api-key.json` (gitignored). Screenshots, URLs, category, age rating, App Privacy, and the build itself are still managed by hand in App Store Connect — fastlane only handles the per-locale text fields.

**Brand vocabulary** (use these exact words; don't drift):
- App name: **GluWink** (never "GluCoach", "Glucoach", etc.).
- We call ourselves a **tool / hulpmiddel** — not "ally", "buddy", "coach".
- Attention framing: "**when something needs your attention** / **als iets je aandacht vraagt**" (deliberately not "when diabetes needs..." — the trigger is broader than just glucose).
- The two states use the same words everywhere: green = "**all clear** / **alles ziet er goed uit**"; red = "**needs attention** / **vraagt aandacht**".

## Renaming the App

The codebase is designed to minimize rename pain. Most user-facing occurrences of "GluWink" are derived from `INFOPLIST_KEY_CFBundleDisplayName` in `Config.xcconfig` at build time.

**To rename, change these:**

1. `Config.xcconfig` — `INFOPLIST_KEY_CFBundleDisplayName` and `INFOPLIST_KEY_NSHealthShareUsageDescription` (single source of truth)
2. `nl.lproj/InfoPlist.strings` — Dutch `NSHealthShareUsageDescription` override (English base comes from xcconfig; iOS doesn't support variable substitution in `.strings` files)
3. `AGENTS.md`, `QUIRKS.md` — documentation references
4. (Optional, cosmetic) Xcode project/target/scheme names — already neutral (`App.xcodeproj`, target `App`, scheme `App`)

**Already neutral (no changes needed on rename):**

- `Localizable.strings` — uses `%@` format specifiers, app name injected via `Constants.displayName`
- `ShieldContent.Strings` fallback — reads `CFBundleDisplayName` from bundle
- Widget display name — reads `CFBundleDisplayName` from bundle
- `ActivityScheduler` interval names — uses `Constants.bundlePrefix`
- Internal Swift types — use generic names (`MainApp`, `StatusWidget`, `StatusEntry`, etc.)
- Swift files and internal package/module names — `App.swift`, `App.entitlements`, `StatusWidgetBundle.swift`, `SharedKit`, etc.
- Xcode project — `App.xcodeproj`, target `App`, scheme `App`, source folder `App/`

## Open Source / Distribution

This project is intended to be open-sourced. Keep this in mind:

- **No secrets in the repo.** No API keys, no hardcoded credentials. (Currently none needed since we use HealthKit.)
- **Bundle identifier and App Group must be configurable.** Other developers will need to change `nl.fokkezb.GluWink` to their own identifier. Document this in the README.
- Add a `README.md` covering: what the app does, device prerequisites, Xcode setup (targets, capabilities, entitlements), how to build and deploy, how to configure allowed apps.
- Add a `LICENSE` file (MIT or similar).
- The check-in rules (glucose thresholds, timing) are hard-coded but should be clearly organized in one place so other parents can adjust them before building.
