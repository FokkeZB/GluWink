## Summary
<!-- 1-3 sentences: what changed and why. -->

## Linked issues
<!-- Use "Closes #N" to auto-close on merge, or "Refs #N" to link without closing. -->
Closes #

## Screenshots / recordings
<!-- Required for any user-visible change. Include light + dark mode if relevant. Delete this section if the change has no UI surface. -->

## Testing
- [ ] Built and run on a physical iPhone (Screen Time APIs don't work in the Simulator)
- [ ] `make deploy` succeeds
- [ ] Tested both EN and NL if any user-facing strings changed
- [ ] If shared App Group state or `ShieldContent` changed: verified widget, watch, and shield extensions still render correctly

## Checklist
- [ ] No hardcoded "GluWink" in Swift code (use `Constants.displayName`; use `%@` in `.strings`)
- [ ] New user-facing strings added to both `en.lproj` and `nl.lproj` (and the matching `InfoPlist.strings` if applicable)
- [ ] No new settings or actions bypass the passphrase gate
- [ ] Read the `QUIRKS.md` / `AGENTS.md` sections relevant to this change
- [ ] If visible UI changed: regenerated App Store screenshots with `make appstore-screenshots` (writes to `iOS/fastlane/screenshots/` and syncs `docs/assets/screenshots/`; CI's `screenshots-sync-check` will fail otherwise)
- [ ] No secrets or `private/` contents committed

## Notes for reviewers
<!-- Anything non-obvious: known limitations, follow-ups, deferred work, things you'd like a closer look at. -->
