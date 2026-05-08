# Security Policy

GluWink shields all apps on a child's iPhone (or an adult's, with deliberate friction) until the user acknowledges their diabetes status. Anything that lets a child bypass the shield without the configured passphrase is a security issue. We take those seriously.

## Supported versions

Only the **latest TestFlight or App Store release** is supported. GluWink is a single-maintainer open-source project — there's no LTS, no backports, no parallel branches. If you're on an older build, please update before reporting.

## Reporting a vulnerability

**Please report privately.** Do not file a public issue.

The primary channel is GitHub's [private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability):

> Go to the repository's **Security** tab → **Report a vulnerability**.

That opens a private advisory only the maintainer and you can see, with a structured template for the details. If you can't use that flow, fall back to the maintainer email at `<MAINTAINER_EMAIL>` (placeholder — see the note in the PR; the maintainer will replace this before merge).

When you report, please include:

- A clear description of the issue and what an attacker can do with it.
- Reproduction steps (on-device steps, sample data, scripts — whatever you have).
- Affected GluWink version (`CFBundleShortVersionString` + build number, visible in Settings).
- iOS version, device model, and any relevant configuration (Family Sharing setup, data source, etc.).

## Disclosure timeline

- **Acknowledgement** within **7 days** of the report.
- **Fix or status update** within **30 days**. If a fix takes longer (third-party dependency, App Review queue, etc.), we'll keep you in the loop in the same advisory thread.
- **Public disclosure** is coordinated with the reporter. We'd prefer to ship a fix in TestFlight / the App Store before the advisory goes public, but we won't sit on a confirmed issue indefinitely.

## In scope

- **Shielding bypass** — any path that removes or sidesteps the shield without the configured passphrase, including misuse of `ManagedSettings`, `DeviceActivity`, App Group state, or the shield extensions.
- **Passphrase / Keychain handling** — weak hashing, salt reuse, plaintext storage, key-extraction routes, brute-force amplification.
- **App Group data exposure** — anything that lets another app on the device read or tamper with GluWink's `group.nl.fokkezb.GluWink` container.
- **Shield extensions** (`ShieldConfig`, `ShieldAction`, `DeviceActivityMonitor`) — re-arm bypasses, dismiss-without-check-in paths, state corruption from extension input.
- **Critical-glucose contract** — anything that lets the shield be dismissed at or above the user-configured critical threshold (per the [check-in rules in `AGENTS.md`](AGENTS.md#check-in-rules-hard-coded), this is supposed to be a hard "no").
- **Data integrity from external sources** — Nightscout response handling, HealthKit sample validation, anything that can be poisoned to spoof a "safe" reading.

## Out of scope

- **Feature requests, UX gripes, missing translations.** Those go in the regular [issue tracker](https://github.com/FokkeZB/GluWink/issues) or [Discussions](https://github.com/FokkeZB/GluWink/discussions).
- **Generic Apple platform issues** (HealthKit returning stale samples on a specific iOS build, FamilyControls UI bugs, etc.) — please file those with Apple via Feedback Assistant.
- **Adults deleting the app from their own device.** This is by design — the adult mode is deliberate friction, not absolute prevention. See [`AGENTS.md` → "For adults"](AGENTS.md#for-adults-self-managing).
- **Children defeating the shield by powering off the device, factory-resetting, asking the parent for the passphrase, etc.** Out-of-band attacks the app cannot defend against.
- **Issues in the `docs/` marketing site** that don't expose user data or affect the iOS app's security posture.

## Out-of-scope licence note

The `LICENSE` shows up as `Other` on GitHub because [PolyForm Noncommercial 1.0](https://polyformproject.org/licenses/noncommercial/1.0.0/) isn't in GitHub's SPDX list. That's deliberate — noncommercial is the point. Not a security issue.
