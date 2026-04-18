# App Store Copy — English (en-US)

Primary / source locale. Every other translation should be able to diff against this file.

See `README.md` for field limits, shared info (URLs, category, privacy, screenshots spec), and how to add a new translation.

---

## App name (30)

```
GluWink
```
*(7 / 30)*

## Subtitle (30)

```
A phone that helps with T1
```
*(26 / 30)*

Alternates if the team prefers a different tone:

- `Diabetes-first screen time` *(26 / 30)*
- `Glucose everywhere, focus too` *(29 / 30)*
- `Diabetes tool, not distraction` *(30 / 30)*

## Promotional text (170)

```
Turn your iPhone and Apple Watch from your biggest distraction into your best tool. Glucose and carbs everywhere. Apps blocked when something needs your attention.
```
*(163 / 170)*

## Description (4000)

```
Make your iPhone and Apple Watch a tool for diabetes — not a distraction from it.

GluWink does three things, and nothing more:

1. Glucose and carbs visible everywhere. Home Screen, Lock Screen and StandBy widgets in every size. Complications on every Apple Watch face. An optional glucose number on the app icon badge. A friendly check-in shield on every unlock.

2. Clear status at a glance. A green face means everything looks good. A red face means something needs attention — glucose is high or low, the sensor is stale, or carbs were never entered for that meal. Every surface speaks the same simple language.

3. Other apps blocked only when something needs your attention. When the face is red, GluWink blocks other apps until the check-in is done. When everything is green, your phone is just your phone. (You can also choose to have the check-in on every unlock, or turn blocking off entirely — the choice is yours.)

— Built for two audiences —

For parents of children with Type 1:
• Set GluWink up once on the child's iPhone using Family Sharing.
• Pick which apps stay free to use (the CGM app, school apps, phone, messages).
• A passphrase only the parent knows protects the settings.
• The child cannot delete the app or skip the check-in.
• You can always glance at the home screen badge or a widget to see how things are going.

For adults managing their own Type 1:
• Authorize GluWink for yourself — no Family Sharing required.
• Have a partner, spouse, or friend set the passphrase. The friction is the point.
• You can always uninstall — GluWink is honest about that. It nudges, it doesn't imprison.

— Where the data comes from —

GluWink reads glucose and carbs from Apple Health. Most CGM apps (Dexcom, Libre, CamAPS, xDrip, Loop, iAPS, and others) already write to Apple Health. If yours does, GluWink is a one-tap connection.

Prefer Nightscout? Connect a Nightscout site instead — handy when a parent is monitoring a child remotely, or when the diabetes system writes to Nightscout but not Apple Health. Both sources can be on at the same time; the most recent reading wins.

Want to try the app first? Demo mode shows realistic glucose and carb data without any sensor.

— What you get —

• Friendly check-in shield with action items based on the current glucose and last carbs.
• Home Screen, Lock Screen, and StandBy widgets in every size, with red / green attention tint.
• Apple Watch app and complications — glucose and carbs at a glance, on every watch face.
• Optional glucose number on the app icon badge.
• Configurable thresholds, intervals, and a daily carb grace period (so 6am cereal isn't an emergency).
• Block apps always, only when attention is needed, or not at all — you decide.
• A short cooldown after the check-in, so the moment is used to actually do the thing.
• English and Dutch throughout.

— Honest about what GluWink is not —

GluWink is not a medical device. It does not replace your CGM, your pump, your endocrinologist, or your judgment. It does not make treatment decisions. It surfaces information that's already on the phone and asks one question: did you do the diabetes thing yet?

— Open source —

GluWink is open source. Your data stays on your device (with HealthKit) or on the Nightscout site you control. There are no accounts, no servers run by us, no analytics, no ads. Source code, build instructions, and the rules engine are all on GitHub.

Type 1 diabetes is relentless. The phone doesn't have to be.
```
*(~3,150 / 4000 — room left for future feature shout-outs)*

## Keywords (100)

```
diabetes,type 1,t1d,glucose,cgm,dexcom,libre,nightscout,carbs,kids,parents,screen time,shield,health
```
*(99 / 100)*

Notes:
- Do **not** repeat words from the app name or category — Apple already indexes those.
- Do **not** put spaces after commas (Apple counts them).
- The plural / singular forms (`carb` vs `carbs`) are also indexed when one is present, so the shorter form is preferred.
- `loop`, `iaps`, `camaps`, `xdrip` are intentionally omitted to avoid trademark friction; they're mentioned in the description instead.

## What's New (4000) — v1.0 launch

```
Hello world.

This is the first public release of GluWink. If you're trying it on your kid's phone, on your own phone, or just to see what it does — thank you. Open an issue or start a discussion on GitHub if anything feels off.

Highlights in 1.0:
• Apple Health and Nightscout data sources, with optional demo mode.
• Friendly check-in shield with red / green status.
• Home Screen, Lock Screen, and StandBy widgets.
• Apple Watch app and complications.
• Passphrase-gated settings for parents and accountability partners.
• Fully localized in English and Dutch.
```
*(~580 / 4000)*

## Screenshot captions

Scene order matches the table in `README.md` → Screenshots.

### iPhone (6.7" / 6.9")

| # | Caption |
|---|---|
| 1 | The shield that turns every unlock into a check-in. |
| 2 | Red when something needs attention. |
| 3 | Glucose and carbs on every screen. |
| 4 | The parent view: status, settings, peace of mind. |
| 5 | Glucose and carbs on every watch face. |
| 6 *(optional)* | Apple Health, Nightscout, or demo — pick one. |

### Apple Watch (45mm)

| # | Caption |
|---|---|
| 1 | Diabetes status on your wrist. |
| 2 | Pick the complications that fit your face. |
