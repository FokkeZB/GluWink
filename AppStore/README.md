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
| 2 | **Red shield** — red face, "Heads up!", glucose high, action checks visible. |
| 3 | **Home Screen widgets** — small + medium + large in a stack, mix of green and red. |
| 4 | **Parent / main app view** — shielding active screen, gear icon, status. |
| 5 | **Apple Watch + complications** — watch face with glucose + carbs complications, plus the Watch app. |
| 6 *(optional)* | **Setup checklist** — Apple Health + Nightscout + demo data choices. |

### Apple Watch scenes (45mm)

| # | Concept |
|---|---|
| 1 | Watch app — green status, glucose + carbs. |
| 2 | Smart Stack / complication selection. |

### Captions

Captions for each scene live in the per-locale file under **Screenshot captions**. Each locale file ships its own translations in the same order.

### Production checklist

- [ ] Render screenshots from a real device (Screen Time UI does not work in the Simulator — see `QUIRKS.md`).
- [ ] Use the same status bar (full battery, full signal, no notifications) — `xcrun simctl status_bar` for any non-shield screens captured in the Simulator.
- [ ] Localize captions on the screenshot itself **and** in the App Store Connect caption field.
- [ ] Avoid real names, school logos, or other identifying information in widget previews.
- [ ] Keep the green/red faces consistent with the app icon variants in `iOS/App/Assets.xcassets/`.

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

### Day-to-day commands

| Command | What it does |
|---|---|
| `make appstore-sync` | Regenerate `iOS/fastlane/metadata/` from `AppStore/*.md`. Validates length limits locally, no network. |
| `make appstore-push` | Sync, then push to App Store Connect. Updates the **editable** version (most recent draft / "Prepare for Submission"). Does **not** submit for review. |
| `make appstore-pull` | Download Apple's current copy into `iOS/fastlane/metadata/` — handy for diffing or bootstrapping a new locale. Read-only; never overwrite the Markdown from this. |

What gets pushed (per locale, from each `<locale>.md`):

- App name → `name.txt`
- Subtitle → `subtitle.txt`
- Promotional text → `promotional_text.txt`
- Description → `description.txt`
- Keywords → `keywords.txt`
- What's New → `release_notes.txt`

What is **not** pushed via fastlane (still managed in App Store Connect by hand):

- URLs (Support / Marketing / Privacy Policy) — they're shared across locales and rarely change. See the URLs section above.
- Category, age rating, App Privacy answers — set once, kept in this README.
- Screenshots and captions — produced from real devices, not yet automated.
- The build itself — uploaded via Xcode / Transporter.

### Adding a new locale

1. Create `AppStore/<locale>.md` (see "Contributing a new translation" above).
2. Run `make appstore-sync` to confirm it parses without errors.
3. In App Store Connect, add the locale to the app version (English UK doesn't auto-create itself).
4. Run `make appstore-push`.

---

## Submission checklist

Before tapping **Submit for Review**:

- [ ] App name, subtitle, promo text, description, keywords, and What's New filled in for every locale the listing supports.
- [ ] Screenshots uploaded for at least one required iPhone size, every locale.
- [ ] Screenshot captions entered per locale.
- [ ] Privacy Policy URL is live and reachable.
- [ ] Support URL is live and reachable.
- [ ] App Privacy questionnaire completed ("Data Not Collected").
- [ ] Age rating questionnaire completed (4+, mild medical info).
- [ ] Sign-in info / demo account section: explicitly say "no account required" and point the reviewer at Demo mode.
- [ ] Reviewer notes: mention that Screen Time + Family Controls require a real device and that the reviewer can use Demo mode in Settings → Data Sources to populate glucose without a CGM.
- [ ] Build uploaded and selected for the version.
- [ ] Pricing set to Free.
- [ ] Availability set to all territories where the listing is localized (at minimum: US, NL, BE).
