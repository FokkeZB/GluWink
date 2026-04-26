# App Store Listing — GluWink

Everything needed to submit GluWink to the App Store, split so new translations are easy to contribute.

## Files

| File | Purpose |
|---|---|
| `README.md` (this file) | Field reference, shared info (URLs, category, privacy, screenshots spec), submission checklist, contribution guide. |
| `en-US.md` | English copy. This is the **primary / source** locale. |
| `nl-NL.md` | Dutch copy. |
| `<locale>.md` | Any additional locales, one file per App Store locale code. |

Apple character limits are noted next to each field in the per-locale files. Anything at the limit is intentional — keep tightening before adding.

---

## Field reference

| Field | Limit | Where in App Store Connect |
|---|---|---|
| App name | 30 | App Information |
| Subtitle | 30 | App Information (per locale) |
| Promotional text | 170 | Version Information (editable without resubmit) |
| Description | 4000 | Version Information |
| Keywords | 100 | Version Information (comma-separated, no spaces after commas) |
| What's New | 4000 | Version Information (per release) |
| Screenshot captions | — | Per screenshot, per locale (optional but recommended) |
| Support URL | — | App Information |
| Marketing URL | — | App Information (optional) |
| Privacy Policy URL | — | App Information (required) |
| Category | — | App Information |
| Age rating | — | App Information |

---

## URLs

The domain is **`gluwink.app`** (GitHub Pages, served from the repo).

- **Support URL:** `https://gluwink.app/support` — page that links to GitHub Issues.
- **Marketing URL:** `https://gluwink.app`
- **Privacy Policy URL:** `https://gluwink.app/privacy` — must exist before submission.

These URLs are the same across every locale. The marketing site itself must have a localized variant (or a language switcher) before the corresponding App Store locale goes live.

## Category

- **Primary:** Medical
- **Secondary:** Health & Fitness

> "Medical" requires a Privacy Policy URL and may trigger extra App Review questions about clinical claims. The description deliberately avoids any treatment claims. If review pushes back, fall back to **Health & Fitness** as primary.

## Age rating

- 4+
- No objectionable content of any kind.
- Medical/Treatment Information: **Infrequent/Mild** (we surface glucose values and suggest "drink water", "eat something", "check pump").

## App Privacy (data collection)

Answer in App Store Connect → App Privacy:

- **Data Not Collected.** GluWink does not collect any data.
- HealthKit data stays on the device.
- Nightscout data is read directly from the user's own Nightscout server; it does not pass through any GluWink-operated server.
- No analytics SDK, no crash reporting SDK, no third-party SDKs.

If a Nightscout-related cloud feature is ever added (e.g. push notifications via APNs through a relay), revisit this section and the Privacy Policy.

---

## Screenshots

App Store Connect requires screenshots for at least one iPhone size (6.7" or newer 6.9"). watchOS screenshots are optional but recommended for Watch-enabled apps.

### Scenes (same across every locale)

Deliver every locale in the **same order** so screenshot #1 is always the same concept.

| # | Concept |
|---|---|
| 1 | **Green shield** — friendly face, "Looking good!", glucose + carbs visible, single Continue button. |
| 2 | **Orange shield** — orange face, glucose high but non-critical, check-in list visible and dismissible. |
| 3 | **Red shield (critical)** — red face, glucose at/above the critical threshold, check-in button hidden and the "shield cannot be dismissed until glucose drops below X" subtitle on-screen. Sells the no-disarm contract. |
| 4 | **Home Screen widgets** — small + medium + large in a stack, mix of green and orange. |
| 5 | **Settings** — parent / main-app chrome: Attention Rules, Shielding On, data sources, glucose unit. |
| 7 | **Setup checklist** — Apple Health + Nightscout + demo data choices. |

### Apple Watch scenes (45mm, 396×484 px)

Scene `06` is split across two captures because one half is manual: Apple provides no API to render a complete watch face with complications, so the face shot is a real hand capture (device preferred; 45mm simulator acceptable) while the app-UI shot is driven by `WatchScreenshotHarness`. Both land in the same flat locale folder as the iPhone PNGs — `fastlane deliver` buckets by pixel dimensions, not subfolders, so 396×484 PNGs route to the Apple Watch Series 7 45mm tier automatically.

| # | Concept | Captured how |
|---|---|---|
| 06 | **Apple Watch face + complications** — glucose + carb complications visible on the wearer's preferred face. Sells "on every watch face". | **Manual.** Owner commits `06_watchFace.png` to `iOS/fastlane/screenshots/<locale>/` and `docs/assets/screenshots/<locale>/`. One per locale. |
| 07 | **Apple Watch app** — green status, glucose + carbs, "Xm ago" relative timestamps. | Auto — `make appstore-screenshots` runs the `watchApp` scene on the 45mm watchOS simulator. |

### Captions

Captions for each scene live in the per-locale file under **Screenshot captions**. They are the single source of truth: `.claude/skills/appstore-screenshots/scripts/capture.sh` parses the "iPhone" table out of `<locale>.md` and passes the matching caption to the app via `-UITest_Caption`, where `CaptionBanner.swift` renders it as a colored banner at the bottom of the shot (green / brand orange / red for the three shield scenes, charcoal otherwise). Apple removed the standalone "caption" field from listings years ago, so there is no separate App Store Connect field to fill in.

### Production checklist

- [ ] Run `make appstore-screenshots` to render the iPhone deck (scenes 01–05, 07_setupChecklist) + the Apple Watch app UI (`07_watchApp`) from the simulators. The in-app `ScreenshotHarness` / `WatchScreenshotHarness` render marketing-equivalent shield, widget, settings, and watch-app scenes without needing the live Screen Time or HealthKit UI, and bake the per-locale caption into the iPhone PNGs (Watch shots have no caption banner — screen too small). See `.claude/skills/appstore-screenshots/SKILL.md` for scene-level flags and locale filters.
- [ ] Capture `06_watchFace.png` manually for every locale and commit alongside the auto-captured PNGs in `iOS/fastlane/screenshots/<locale>/` (see SKILL.md → "Manual shots" for resolution + complication requirements). Without it, the Watch deck on App Store Connect ships with only one shot, which is legal but undersells the integration.
- [ ] Status bar on iPhone shots is locked to 9:41, full signal, full battery by the capture script — no extra `xcrun simctl status_bar` commands needed. Watch shots don't have an iOS status bar to override.
- [ ] Avoid real names, school logos, or other identifying information in widget previews or the watch face.
- [ ] Keep the green/red faces consistent with the app icon variants in `iOS/App/Assets.xcassets/` and `iOS/WatchApp/Assets.xcassets/`.

---

## Contributing a new translation

1. Copy `en-US.md` to `<locale>.md`, where `<locale>` is the App Store locale code (e.g. `fr-FR`, `de-DE`, `es-ES`, `pt-BR`). Apple's full list lives in the [App Store Connect Help](https://developer.apple.com/help/app-store-connect/reference/app-store-localizations/).
2. Translate every field. Keep the structure (headings, fenced code blocks, character-count footnotes) identical so reviewers can diff against `en-US.md`.
3. Stay within the character limits shown in parentheses next to each field. After translating, update the count in the footnote (e.g. `*(168 / 170)*`).
4. Keep `GluWink` as the app name in every locale — it's a proper noun.
5. Do **not** translate URLs, the privacy answer, the category, or the age rating — those live in this README and are shared across locales.
6. Translate the **screenshot captions** in the same order as the scene table above. If a caption doesn't fit naturally, rewrite it rather than translate literally — screenshots are marketing, not manuals.
7. Follow the notes under **Keywords** in your locale file:
   - Do not repeat words from the app name or the category (Apple already indexes those).
   - Do not put spaces after commas (Apple counts them).
   - Pick the form most users actually search for (usually plural, but depends on the language).
   - Avoid trademarked brand names you aren't sure about.
8. Open a pull request. A native speaker review is appreciated before merging.

Once the translation is merged, it still needs to be entered into App Store Connect for the matching locale and have its own screenshots produced.

---

## Pushing to App Store Connect (fastlane)

The Markdown files in this folder are the source of truth. They get converted to fastlane's per-field text layout and pushed to App Store Connect via `fastlane deliver`.

### One-time setup

1. **Install Ruby + bundler.** macOS' system Ruby is too old; use Homebrew:

   ```sh
   brew install ruby
   echo 'export PATH="/opt/homebrew/opt/ruby/bin:$PATH"' >> ~/.zshrc
   exec zsh
   gem install bundler
   ```

2. **Install fastlane into the project's vendored bundle:**

   ```sh
   make appstore-bootstrap
   ```

   This reads `iOS/Gemfile` and installs into `iOS/vendor/bundle/` (gitignored), so global Ruby stays untouched.

3. **Create an App Store Connect API key.** App Store Connect → Users and Access → Integrations → Keys → "+". Pick role **App Manager** (or higher). Download the `.p8` file — Apple only lets you download it once.

4. **Save the key as JSON** at `private/asc-api-key.json` (the `private/` folder is gitignored):

   ```json
   {
     "key_id": "ABCDE12345",
     "issuer_id": "00000000-0000-0000-0000-000000000000",
     "key": "-----BEGIN PRIVATE KEY-----\n…contents of the .p8 file…\n-----END PRIVATE KEY-----",
     "in_house": false
   }
   ```

   The `key` field must be a single string with literal `\n` for newlines, or one big multi-line string — both work.

5. **Fill in App Review Contact Info** at `private/asc-review-info.json` (also gitignored — a template is committed only via this README; the actual file lives in `private/`):

   ```json
   {
     "first_name": "Jane",
     "last_name": "Doe",
     "phone_number": "+31 6 1234 5678",
     "email_address": "jane@example.com",
     "demo_user": "",
     "demo_password": "",
     "notes": "GluWink does not require an account. To populate glucose data without a CGM, open Settings → Data Sources → enable Demo mode. Note: Screen Time blocking uses Family Controls, which only works on a real device — not the iOS Simulator."
   }
   ```

   Apple rejects pushes with blank `first_name`, `last_name`, `phone_number`, or `email_address`. The phone number must include the country-code prefix (`+31 …`, `+1 …`). `demo_user` and `demo_password` can be empty strings — GluWink doesn't require an account.

   If this file is missing, `make appstore-push` still works for text-only updates but logs a warning and skips the contact-info upload. Submission for review will fail until the contact info is set, either via this file or directly in App Store Connect.

### Day-to-day commands

| Command | What it does |
|---|---|
| `make appstore-sync` | Regenerate `iOS/fastlane/metadata/` from `AppStore/*.md`. Validates length limits locally, no network. |
| `make appstore-push` | Sync, then push to App Store Connect. Updates the **editable** version (most recent draft / "Prepare for Submission"). Does **not** submit for review. |
| `make appstore-pull` | Download Apple's current copy into `iOS/fastlane/metadata/` — handy for diffing or bootstrapping a new locale. Read-only; never overwrite the Markdown from this. |
| `make appstore-beta` | Archive a Release build and upload to TestFlight. Auto-bumps the build number from ASC. See "Releasing a TestFlight build" below. |

What gets pushed (per locale, from each `<locale>.md`):

- App name → `name.txt`
- Subtitle → `subtitle.txt`
- Promotional text → `promotional_text.txt`
- Description → `description.txt`
- Keywords → `keywords.txt`
- What's New → `release_notes.txt`

Locale-less fields:

- Copyright → `copyright.txt`, derived from the top-level `LICENSE` file (`Copyright (c) YYYY Holder` line; "(c)" and any trailing "and contributors" are stripped — Apple auto-prepends the © glyph).

What is **not** pushed via fastlane (still managed in App Store Connect by hand):

- URLs (Support / Marketing / Privacy Policy) — they're shared across locales and rarely change. See the URLs section above.
- Category, age rating, App Privacy answers — set once, kept in this README.
- The build itself — `make appstore-beta` uploads it to TestFlight (see the "Releasing a TestFlight build" section below). `make appstore-push` stays text-only via `skip_binary_upload true` in `Deliverfile`, so it's safe to re-run without touching the binary.

Screenshots _are_ pushed by `make appstore-push` now (captions baked in on iPhone, `skip_screenshots false` in `Deliverfile`). The push ships **both** iPhone 6.9" (1320×2868 px) and Apple Watch 45mm (396×484 px) decks in one sweep — fastlane routes each PNG to its display tier based on pixel dimensions, so they coexist in the flat `iOS/fastlane/screenshots/<locale>/` folder. Regenerate the auto-captured shots with `make appstore-screenshots` first so ASC gets the latest deck; the manual `06_watchFace.png` stays on disk across runs and is picked up alongside.

### Adding a new locale

1. Create `AppStore/<locale>.md` (see "Contributing a new translation" above).
2. Run `make appstore-sync` to confirm it parses without errors.
3. In App Store Connect, add the locale to the app version (English UK doesn't auto-create itself).
4. Run `make appstore-push`.

---

## Releasing a TestFlight build

`make appstore-beta` takes the current `main` checkout to a pending TestFlight build — archive, sign, upload — in one command.

### What it does

1. Calls App Store Connect to find the latest build number across all versions and picks the next integer. Never collides with an existing build, never prompts for a manual bump.
2. Runs `xcodebuild archive` with `-allowProvisioningUpdates`, so Xcode-managed signing can create or renew the App Store distribution profile on its own.
3. Exports the archive as an `app-store` `.ipa` into `iOS/build/` (gitignored).
4. Uploads the `.ipa` to TestFlight via the same App Store Connect API key used for metadata pushes. `skip_waiting_for_build_processing` is on, so the lane returns as soon as Apple acknowledges the upload — the build appears under **TestFlight → Builds** within a few minutes.

The marketing version (`MARKETING_VERSION` in the xcodeproj, shown to users as "1.0") is **not** touched. Bumping that is a deliberate release step tracked under #33. Build numbers, on the other hand, are bookkeeping and move every upload.

### Prerequisites

On top of the metadata setup above:

- **Family Controls Distribution** approved by Apple for team `Y39937U7XN` — request at https://developer.apple.com/contact/request/family-controls-distribution/. The form is short (name, email, team ID, acceptance of the Apple Developer License Agreement attesting to one of two primary purposes — parental supervision via Family Sharing, or individual personal device-usage management) but it is still **manually reviewed**. After submitting, the page reads "Thank you for your submission. We'll review your request and contact you soon with a status update." — approval lands by email, typically days to a few weeks. Apple grants the **Development** variant of the capability automatically; the **Distribution** variant is what this manual review unlocks. Without it, archive succeeds but `xcodebuild -exportArchive` fails because the auto-generated **Store** profile cannot include `com.apple.developer.family-controls`. App Store Review later evaluates the shipped app against the same primary purposes under guideline 5.5 — make sure App Review notes spell out the medical use case (see Production checklist below). See `QUIRKS.md` → "Family Controls Distribution requires Apple's manual review" for the full story.
- Signed into Xcode at least once with an Apple ID on team `Y39937U7XN` (the one in `DEVELOPMENT_TEAM`). `-allowProvisioningUpdates` talks to that session to fetch the App Store profile.
- The App target still has `CODE_SIGN_STYLE = Automatic`. If you ever flip it to manual, this lane needs an `export_options.provisioningProfiles` override and re-signing notes.
- `private/asc-api-key.json` is the one with role **App Manager** or higher — "Developer" can read but not upload.

### Running it

```sh
make appstore-beta
```

First run takes 3–5 minutes (clean archive + upload); subsequent runs are similar because we `clean: true` every time to avoid "phantom fixed" builds from cached derived data.

Running it again picks a new build number automatically — the lane is safe to re-run as often as needed.

### Checking it worked

- The lane's last log line should be `Successfully uploaded the new binary to App Store Connect`.
- Within ~5 minutes, the build shows up under **App Store Connect → TestFlight → Builds** in "Processing" state.
- Once it flips to "Ready to Test", internal testers see it automatically; external distribution is a separate click in ASC.

### When it fails

- **`Provisioning profile "iOS Team Store Provisioning Profile: nl.fokkezb.GluWink…" doesn't include the Family Controls (Development) capability` / `…doesn't include the com.apple.developer.family-controls entitlement`** — repeated for the App, ShieldConfig, ShieldAction, and DeviceActivityMonitor targets, with `** EXPORT FAILED **` and `Exit status: 70` at the end. The archive built fine; the Distribution profile is missing the entitlement because Apple hasn't approved the Family Controls Distribution request for this team yet. Submit the form linked in the Prerequisites above (or wait for the status email if you've already submitted — resubmitting doesn't speed it up) and re-run the lane after approval lands. `-allowProvisioningUpdates` will regenerate the Store profile with the entitlement on the next archive. There is no code workaround — stripping the entitlement breaks the app, and ad-hoc / development export can't go to TestFlight. The misleading "(Development)" wording in the error means the profile only carries the auto-granted Development variant, not the Distribution variant the binary needs.
- **"Cannot find a matching profile"** — sign into Xcode with an account on the `DEVELOPMENT_TEAM` and retry. `-allowProvisioningUpdates` can create profiles but not conjure accounts.
- **"The bundle version must be higher than the previously uploaded version"** — you're uploading faster than ASC indexes. Wait 30s and rerun; `latest_testflight_build_number` will see the new build and bump past it.
- **"Invalid API key"** — the key lost its upload role, or expired. Recreate at App Store Connect → Users and Access → Integrations → Keys, save over `private/asc-api-key.json`.

---

## Submission checklist

Before tapping **Submit for Review**:

- [ ] App name, subtitle, promo text, description, keywords, and What's New filled in for every locale the listing supports.
- [ ] Screenshots uploaded for at least one required iPhone size, every locale (`make appstore-push` now also uploads them; captions are baked into each PNG from `AppStore/<locale>.md`).
- [ ] Privacy Policy URL is live and reachable.
- [ ] Support URL is live and reachable.
- [ ] App Privacy questionnaire completed ("Data Not Collected").
- [ ] Age rating questionnaire completed (4+, mild medical info).
- [ ] Sign-in info / demo account section: explicitly say "no account required" and point the reviewer at Demo mode.
- [ ] Reviewer notes: mention that Screen Time + Family Controls require a real device and that the reviewer can use Demo mode in Settings → Data Sources to populate glucose without a CGM.
- [ ] Build uploaded (run `make appstore-beta`) and selected for the version.
- [ ] Pricing set to Free.
- [ ] Availability set to all territories where the listing is localized (at minimum: US, NL, BE).
