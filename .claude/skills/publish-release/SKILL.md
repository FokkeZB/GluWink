---
name: publish-release
description: Ship a new GluWink release to the App Store. Use when the user says "release", "ship a new version", "publish", "let's get a new version out", "submit to App Store", or any variant. Handles the full release cycle: pre-flight checks → version decision → copy validation → `make release VERSION=x.y.z SUBMIT=1` → PR for the bump commit. Never merges, never force-pushes.
allowed-tools: Bash(mise install:*), Bash(gh issue:*), Bash(gh pr:*), Bash(gh api:*), Bash(git status:*), Bash(git log:*), Bash(git pull:*), Bash(git push:*), Bash(make:*), Bash(grep:*), Bash(sed:*), Bash(cat:*), Read, Write, StrReplace
---

# publish-release

End-to-end skill for shipping a new GluWink version to the App Store. Covers:

1. Pre-flight checks (clean tree, on `main`, prerequisites)
2. Version decision
3. App Store copy validation (`make appstore-sync`)
4. Screenshots freshness check
5. Run `make release VERSION=x.y.z SUBMIT=1`
6. Handle any failures (known failure modes documented below)
7. Merge PR for version bump commit

The owner stays in the loop for: version decision, copy changes, and final merge. Everything else is automated.

---

## Step 1 — Pre-flight

Run these in parallel:

```bash
# Are we on main and clean?
git status
git log --oneline -5

# What's the current version?
grep -E "MARKETING_VERSION|CURRENT_PROJECT_VERSION" iOS/App.xcodeproj/project.pbxproj | sort -u

# Any open release-blocking issues?
gh issue list --repo FokkeZB/GluWink --label "P0" --state open
```

Also check that prerequisites are present:

- `private/asc-api-key.json` exists
- `private/asc-review-info.json` exists
- Xcode is open (needed for `make build` / archiving via the MCP or xcodebuild)

If the working tree is dirty, stop and ask the owner to commit or stash.

---

## Step 2 — Version decision

Look at the changes since the last tag:

```bash
git log $(git describe --tags --abbrev=0)..HEAD --oneline
```

Propose a version bump:

| Change type | Bump |
|---|---|
| New user-visible feature (e.g. new data source, new mode) | Minor (1.x.0) |
| Bug fixes / polish only | Patch (1.0.x) |
| Breaking change / major rework | Major (x.0.0) |

Present the proposal and ask the owner to confirm or override.

---

## Step 3 — App Store copy validation

**Always run `make appstore-sync` before starting the build.** It validates character limits for all locales in seconds; the same check runs 10 minutes into `make release` after the archive is done — catching it here is far cheaper.

```bash
make appstore-sync
```

If it reports limit violations, fix `AppStore/en-US.md` and `AppStore/nl-NL.md` and re-run until clean. Common overruns:

- **Description (4000)**: tighten verbose passages — the three-colour signal explanation and the data-source list are historically the longest.
- **Keywords (100)**: drop brand names that are already in the description (`medtrum`, `shield`/`schild`). No spaces after commas.
- **Promo text (170)**: Dutch is usually longer than English — trim adjectives first.

Also check that **What's New** for the upcoming version is filled in for both locales in the per-locale `.md` files. Users see it in the App Store update prompt.

Commit any copy fixes before proceeding:

```bash
git add AppStore/ && git commit -m "fix(appstore): trim copy to fit App Store limits"
git push origin HEAD:fix/appstore-copy
# open PR, get merged, then pull
```

---

## Step 4 — Screenshots freshness (optional)

If UI changed since the last release run `make appstore-screenshots` first — `make release` pushes whatever is currently in `iOS/fastlane/screenshots/`. Use the `appstore-screenshots` skill for this.

The CI check "Verify docs/assets/screenshots/ matches the App Store deck" will catch a stale sync on the version-bump PR. Run `bash docs/scripts/sync-screenshots.sh` after regenerating screenshots, commit, and push.

---

## Step 5 — Run the release

```bash
make release VERSION=<version> SUBMIT=1
```

This runs in the background — it takes 10–20 minutes (archive + upload). Monitor for errors. Known failure modes and fixes are documented in Step 6.

On success the lane:
- Commits `chore: bump to v<version> (<build>)` locally
- Uploads the binary and pushes metadata to App Store Connect
- Runs precheck and submits for App Review
- Pushes the bump commit to `release/v<version>` (not `main` — branch protection)
- Opens a PR automatically

---

## Step 6 — Known failure modes

### App Store copy over limits
```
ERROR: metadata exceeds App Store limits:
  en-US/description.txt: XXXX chars (limit 4000)
```
Fix: edit `AppStore/<locale>.md`, run `make appstore-sync` until clean, commit + push as a PR, merge, pull, re-run. See Step 3.

### `undefined method 'create' for class Spaceship::ConnectAPI::AppStoreVersion`
The `AppStoreVersion.create` class method was removed in fastlane 2.235. Fixed in the Fastfile (`ensure_app_store_version!` now uses `app.ensure_version!`). If it recurs, check `QUIRKS.md → Fastlane`.

### `commit_version_bump` — "No file changes picked up"
Happens when a prior fix PR accidentally already committed the version bump. Fixed in the Fastfile: build number now uses `max(latest_tf_build, current_build) + 1`. If it recurs, manually bump `CURRENT_PROJECT_VERSION` in `iOS/App.xcodeproj/project.pbxproj` by 1 and commit.

### `git push origin main:main` rejected (branch protection)
Fixed in the Fastfile: the lane now pushes to `release/vX.Y.Z` and opens a PR. If the push step still fails, push manually:
```bash
git push origin HEAD:release/v<version>
git push origin --tags
gh pr create --head release/v<version> --title "chore: bump to v<version>" --body "Version bump from make release."
```

### altool upload hangs or fails
See `QUIRKS.md → altool upload failures on Xcode 26 / macOS 26`. The upload takes ~20 minutes — do not interrupt it.

### `ensure_app_store_version!` — "An editable App Store version X.Y.Z already exists"
A previous partial run created the version in ASC but didn't finish. Options:
- If the previous run also uploaded the binary: just submit directly in App Store Connect, skip `make release`.
- If not: delete the version in ASC (App Store Connect → App → Version → delete) and re-run.

---

## Step 7 — Post-release

After the lane succeeds:

1. **Merge the PR** — the version bump PR (`release/v<version>`) lands the bump on `main`. Merge it.
2. **Pull main**:
   ```bash
   git pull --rebase origin main
   ```
3. **Move the roadmap card** (if the release shipped a tracked issue):
   ```bash
   gh project item-edit --id <item-id> --field-id PVTSSF_lAHOACkwkc4BVH4yzhQl0Wc --single-select-option-id a17042c6 --project-id PVT_kwHOACkwkc4BVH4y
   ```
4. **Update `AppStore/<locale>.md`** — move the "What's New — upcoming" block to "What's New — vX.Y" and add a fresh "upcoming" placeholder for next time.

---

## Reference — Fastfile lanes

| Command | What it does |
|---|---|
| `make appstore-sync` | Validate + regenerate `iOS/fastlane/metadata/` from `AppStore/*.md`. No network. |
| `make appstore-push` | Sync + push metadata (no binary). |
| `make appstore-beta` | Archive + upload to TestFlight only (no App Store submission). |
| `make release VERSION=x.y.z` | Bump, archive, push metadata + binary. Staged in ASC, no submission. |
| `make release VERSION=x.y.z SUBMIT=1` | Same + precheck + submit for review. |
