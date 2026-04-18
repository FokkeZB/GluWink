---
name: git-commit
description: Write Conventional Commits messages and commit changes for the GluWink repo. Use when the user asks to commit, says "commit", or completes a chunk of work that should be saved to git.
---

# Git commits — GluWink

This repo uses [Conventional Commits](https://www.conventionalcommits.org/) with project-specific scopes. Apply this skill whenever you create a commit so history stays parseable, releaseable, and pleasant to read.

## Format

```
<type>(<scope>): <subject>

<body>

<footer>
```

- **Subject**: imperative mood, no trailing period, ≤ 72 chars. "add fastlane lane", not "added fastlane lane" or "Added fastlane lane.".
- **Body** (optional but encouraged for non-trivial changes): explain **why**, not what. Wrap at 72 chars. Separate from subject with a blank line. Reference Apple/iOS quirks the change works around (link `QUIRKS.md` if so).
- **Footer** (optional): `Closes #N`, `Refs #N`, or `BREAKING CHANGE: …`.
- **Never** add `Co-authored-by: Claude/Cursor/GPT/...` trailers. Solo project, the human owns the commit.

## Types

| Type | When |
|---|---|
| `feat` | New user-visible feature, new lane, new screen, new behavior. |
| `fix` | Bug fix — something that was broken now works. |
| `refactor` | Internal restructure with no behavior change. |
| `perf` | Performance improvement with no behavior change. |
| `docs` | Documentation only (`.md` files, comments). |
| `chore` | Tooling, config, dependencies, project plumbing. |
| `build` | Build system / Makefile / Xcode project settings. |
| `style` | Formatting, whitespace, lint fixes only. |
| `test` | Adding or updating tests. |
| `revert` | Reverting an earlier commit. |

If a change is genuinely cross-cutting (e.g. "rename the app"), drop the scope and write a clear subject.

## Scopes

Pick the narrowest scope that still covers the change. Common scopes for this repo:

| Scope | Covers |
|---|---|
| `ios` | Main iOS app target (`iOS/App/`). |
| `watch` | Apple Watch app (`iOS/WatchApp/`, `iOS/WatchShared/`, `iOS/WatchWidget/`). |
| `widgets` | Status widget extension (`iOS/StatusWidget/`). |
| `shield` | Shield extensions (`iOS/ShieldConfig/`, `iOS/ShieldAction/`, `iOS/DeviceActivityMonitor/`). |
| `health` | HealthKit integration. |
| `nightscout` | Nightscout integration. |
| `i18n` | Strings files, localization-only changes. |
| `appstore` | `AppStore/`, fastlane pipeline, App Store Connect plumbing. |
| `agents` | `AGENTS.md`, `.claude/`, `.cursor/`, `.mcp.json`. |
| `docs` | Top-level docs (`README.md`, `QUIRKS.md`, `CONTRIBUTING.md`). |
| `build` | `Makefile`, `Config.xcconfig`, `*.xcodeproj` project-level settings. |

Multi-scope changes: prefer splitting into separate commits. If splitting isn't worth it, drop the scope.

## Examples

Good:

- `feat(appstore): add fastlane pipeline for metadata pushes`
- `fix(shield): show carbs even when HealthKit returns no entries today`
- `fix(widgets): respect 4h staleness threshold on Lock Screen widget`
- `docs(appstore): document Apple's v1.0 release-notes silent skip`
- `chore(agents): point future agents at make appstore-push`
- `refactor(ios): extract HealthKitManager from ContentView`
- `build: add iOS/build/ to gitignore`

Bad (and why):

- `Update files` — no type, no scope, no signal.
- `feat: stuff` — vacuous subject.
- `fix(app): Fixed a bug.` — past tense, capital, period, vague subject.
- `feat(ios): add HealthKit + add Nightscout + fix shield bug` — three commits crammed into one.
- `Co-authored-by: Claude <noreply@anthropic.com>` — drop it.

## Workflow

1. **Inspect first.** Run these in parallel before composing the message:
   - `git status` — see all untracked + staged + unstaged.
   - `git diff` — unstaged.
   - `git diff --cached` — staged.
   - `git log --oneline -10` — match the existing tone (skip if there are no commits yet).
2. **Always split into commits that tell a story.** The default is multiple commits, not one. Before staging anything, read the full diff and identify the distinct stories in it — each logical change (a feature, a fix, a refactor, a doc update) gets its own commit. A reader skimming `git log --oneline` should be able to reconstruct *why* the working tree moved from A to B, one beat at a time. Only fall back to a single commit when the diff genuinely is one story (e.g. a one-line typo fix). When in doubt, split.
   - Group by **intent**, not by file. Two files edited for the same reason → one commit. One file edited for two reasons → two commits (split with `git add -p`).
   - Order commits so each one stands on its own and the repo builds/runs at every step. Docs-only reframes before the code that motivates them; infra/plumbing before the feature that uses it; feature before the doc that describes it — whichever order makes each commit self-contained.
   - Stage selectively: `git add <path>` for whole files, `git add -p <path>` for hunk-level splits. `printf 'n\ny\nq\n' | git add -p <path>` works non-interactively when you know which hunks to pick.
   - After each commit, re-run `git status` + `git diff` to make sure the remaining diff is exactly the next story — no stragglers, no accidental drops.
3. **Verify before committing.** Run `git status` again to confirm only the intended files are staged.
4. **Use a HEREDOC** so multi-line bodies survive shell quoting:

   ```bash
   git commit -m "$(cat <<'EOF'
   feat(appstore): add fastlane pipeline for metadata pushes

   AppStore/<locale>.md is the editorial source of truth. A small Ruby
   converter renders it into the per-field text layout fastlane expects,
   then `deliver` pushes via the App Store Connect API key in
   private/asc-api-key.json (gitignored).

   Works around the deliver crash on brand-new versions by pre-creating
   an empty AppStoreReviewDetail record before upload — see Fastfile
   ensure_review_detail!.
   EOF
   )"
   ```

5. **Don't push automatically.** Push only when the user explicitly asks. The remote is `git@github.com:FokkeZB/GluWink.git`. When the user does ask, push once after all the split commits have landed — not between each one.

## Pre-flight safety

Before committing, double-check:

- [ ] No files inside `private/` are staged (API keys, drafts, secrets).
- [ ] No build artifacts (`.build/`, `iOS/build/`, `iOS/vendor/bundle/`, `iOS/fastlane/metadata/`, `*.xcuserdata`).
- [ ] No `.DS_Store`.
- [ ] If you touched user-facing copy, the matching surfaces in `AGENTS.md` → "Marketing Copy" are also updated (or call it out in the body).
- [ ] If you added a new Swift file, it was added to the Xcode project via `XcodeWrite` (otherwise the build will break).

If any of these slip in, **don't amend a pushed commit** — make a follow-up `chore: …` commit instead.
