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

### Tool versions

All toolchain pins live in **`mise.toml`** at the repo root — Ruby, `gh`, `jq`. One file, one install command:

```sh
brew install mise                              # one-time
echo 'eval "$(mise activate zsh)"' >> ~/.zshrc # one-time, then `exec zsh`
mise install                                   # in this repo
```

When bumping a pin: edit `mise.toml`, run `mise install`, commit. Skills assume pinned versions are present and don't carry version-detection or REST workarounds — bump the floor instead. Canonical example: `gh ≥ 2.80` clears the [`gh pr edit` classic-projects deprecation bug](https://github.com/cli/cli/issues/12640).

`.claude/skills/plan-next/SKILL.md` runs `mise install --quiet || true` at the top of its workflow as belt-and-braces (auto-installs after a pin bump; `|| true` swallows install failures from tools in your *global* `~/.tool-versions` that this repo doesn't care about).

### Agent terminal allowlist

The **Self-managed planning loop** (below) needs the agent to invoke a curated subset of `gh` (and `git worktree`, `jq`) without prompting on every call, **and** to reach `api.github.com` without re-asking for network permission on every call. Two separate concerns, two separate mechanisms — and Cursor's mechanisms aren't quite the same as Claude Code's, so the curated set is shipped four ways, each doing the most it can:

| Layer | File | What it controls | Scope | Cross-agent? |
|---|---|---|---|---|
| Per-skill (in-skill calls only) | `.claude/skills/*/SKILL.md` frontmatter `allowed-tools:` | Terminal commands | Active during that skill | **Yes** — Claude Code & Cursor |
| Repo-pinned global (Claude Code) | `.claude/settings.json` (`permissions.allow` / `deny`) | Terminal commands | Always-on, this repo | Claude Code only |
| Repo-pinned global (Cursor — terminal) | **`.cursor/permissions.example.json`** — Cursor doesn't read this; copy it into `~/.cursor/permissions.json` | Terminal commands | Always-on, all of your Cursor | Cursor only, **manual install** |
| Repo-pinned global (Cursor — sandbox/network) | **`.cursor/sandbox.json`** — Cursor reads this automatically | Sandbox network allowlist (e.g. `api.github.com`) | Always-on, this repo | Cursor only, automatic |

**Why four?** The first layer is the only true cross-agent one, but it only fires when the matching skill is active — useless if you ask "create an issue" in a fresh chat with no skill triggered. Claude Code lets us repo-pin a global terminal allowlist (`.claude/settings.json` is read automatically) and doesn't sandbox network. Cursor splits the concern: its **terminal allowlist** is documented as [per-user only — no per-project override](https://cursor.com/docs/reference/permissions.md), so the best we can do is ship a tracked example and tell each contributor to merge it locally; its **sandbox/network policy** ([`.cursor/sandbox.json`](https://cursor.com/docs/reference/sandbox.md)) **does** support a repo-level file, so we ship that one committed and Cursor picks it up automatically.

#### Installing / re-syncing the Cursor allowlist

One command — additive, idempotent, safe to re-run after every pull that touches `.cursor/permissions.example.json`:

```sh
make cursor-perms-sync
```

Under the hood it copies `.cursor/permissions.example.json` to `~/.cursor/permissions.json` if you don't have one yet, otherwise it `jq`-merges the `terminalAllowlist` arrays so any personal entries you've added survive. Cursor re-reads the file on save — no restart.

The allowlist only fires when **Auto-Run** is on (Settings → Cursor Settings → Agents → Auto-Run, set to *Run in Sandbox* or *Run Everything*). In *Ask Every Time* mode the allowlist is ignored, by design.

**When the curated set changes** (someone adds an entry to `.cursor/permissions.example.json`), re-run `make cursor-perms-sync` after pulling. The sync target only adds entries — it never removes them — so a tightening change (entry deleted upstream) stays in your local file until you prune it by hand. That's deliberate: Cursor's `permissions.json` is global across all your projects, so we err on the side of not yanking entries another project of yours might rely on.

#### Cursor sandbox/network (`.cursor/sandbox.json`)

Unlike `permissions.json`, **Cursor reads `.cursor/sandbox.json` directly from the repo** ([docs](https://cursor.com/docs/reference/sandbox.md)) — no manual install. The committed file is intentionally minimal:

- `type: workspace_readwrite` — the agent can read/write anywhere in the repo workspace, but writes outside the workspace are blocked. This is the meaningful guard: it prevents the agent from accidentally clobbering `~/.gitconfig`, `~/.ssh/`, or any other personal config while iterating in this repo. Per-user write exceptions (e.g. for global git hooks like the zapier-omni-hook log dir) belong in `~/.cursor/sandbox.json` via `additionalReadwritePaths`, not in the committed file.
- `networkPolicy.default: allow` — no per-host filtering. We tried a curated allow list (`api.github.com`, `*.githubusercontent.com`, `github.com`, `uploads.github.com`) but it added friction without adding security: the planning loop's safety net is the curated terminal allowlist + explicit denies in `.claude/settings.json`, not "the agent can't reach random hosts". For a single-maintainer repo where you trust the allowlist, network sandboxing is theatre.

If you want to *re-enable* per-host network filtering for your own clone — e.g. you're paranoid about a compromised dependency — set `networkPolicy.default: "deny"` plus an explicit `allow` list in your `~/.cursor/sandbox.json`. Allow lists are unioned across the repo file and yours, but `deny` always wins, so you can tighten unilaterally.

#### Curated set (what's in, what's out)

Both `.claude/settings.json` and `.cursor/permissions.example.json` ship the same curated set:

- **`gh` subset**: read-heavy commands (`issue`/`pr`/`project`/`repo`/`release`/`run`/`workflow`/`label` `view|list|diff|checks`), the writes the planning loop needs (`issue create|edit|comment|close`, `pr create|edit|comment|ready`, `project item-add|edit|archive`), and `gh api graphql` + `gh api repos/FokkeZB/` for the few REST sidesteps the loop relies on. **Label writes** (`gh label create|edit|delete|clone`) are excluded — repo label taxonomy is ours to curate by hand, not for the agent to reshape mid-task.
- **`git`**: `worktree`, `status`, `log`, `diff`, `branch`, `fetch`, `push`, `show`. `git push` is allowed so subagents can publish their branches; the explicit denies below catch the dangerous variants on Claude Code, and on Cursor the prefix-match limitation means *you* stay in the loop on `git push --force` / `git push origin main`.
- **`mise`**: `install`, `exec`, `current`, `ls`, `trust`.
- **`make`** (specific safe targets only — see deny list for what's excluded): `build`, `install`, `deploy`, `tunneld`, `docs-bootstrap|build|clean|serve|publish-check|audit|sync-screenshots`, `appstore-sync|pull`, `screenshot`, `venv-clean`, `cursor-perms-sync`. `install`/`deploy` push the current build to the connected iPhone — that's a side effect on a physical device, but it's the inner loop of every test cycle and the device itself is the gate (must be unlocked + USB-attached), so the prompt friction wasn't earning its keep. `tunneld` needs `sudo` and will still prompt for your password interactively — allowlisting just removes the *agent's* prompt, not the OS's. We deliberately do **not** allow bare `make` — Cursor has no deny list, so a wildcard would also auto-run `make appstore-push` (pushes to App Store Connect), `make appstore-beta` (uploads TestFlight build), etc.
- **`xcodebuild`** (any args). Used as the build-verification fallback when the Xcode MCP bridge is stale (see "When the bridge goes stale" in the Xcode MCP section). Wildcarded because the canonical invocation is long and varies by destination/configuration, and `xcodebuild` itself doesn't push, doesn't touch App Store Connect, and doesn't deploy to device — those side-effecting workflows live behind `make appstore-*` / `make install` / `make deploy` and are gated separately.
- **`swift test`** and **`swift build`** (any args). SwiftPM dev loop for the `iOS/SharedKit` package. Needed to run the `ThresholdResolverTests` / `SettingsValidationTests` suites without the Xcode project round-trip, which also matters for Cursor: without the allowlist entry, Cursor's workspace sandbox wraps the invocation in `sandbox-exec` and SwiftPM's own `sandbox-exec` nesting fails with `Operation not permitted`. Allowlisted = runs outside the sandbox, tests just work. Scoped to `test` / `build`; plugin-executing subcommands (`swift package …`, `swift run`) stay out.
- **`xcrun simctl list`** (only `list`). Lets the agent inspect simulator state — booted devices, runtimes, app containers — without being able to mutate it. Mutating `simctl` subcommands (`boot`, `install`, `erase`, `io`, `status_bar`, `launch`, `terminate`) are deliberately not on the allowlist: the screenshot capture script (`bash .claude/skills/appstore-screenshots/scripts/capture.sh`) calls them as subprocesses inside an already-allowlisted bash invocation, so it works end-to-end without the agent gaining a separate handle to the destructive ops. Per AGENTS.md → "Things that WILL NOT work" we don't simulator-test the app proper anyway, so the read-only `list` covers the legitimate "what's running?" use cases.
- **`bash` scoped to repo scripts**: `bash .claude/skills/` and `bash docs/scripts/` — every skill and audit script lives under one of these prefixes, so the allowlist matches them without opening the door to arbitrary `bash`.
- **Plain Unix utilities** for inspecting output: `ls`, `cat`, `head`, `tail`, `sed`, `awk`, `wc`, `sort`, `uniq`, `echo`, plus `jq` and `cd`. None of them mutate state; chains like `… && tail -40` or `… | sed -n '70,80p'` work without prompting.

**Deliberately excluded** so you stay in the loop:

- `gh pr merge` — owner merges, always.
- `gh release create|delete|edit` — App Store-adjacent.
- `gh repo edit|delete|archive`.
- `gh workflow run|enable|disable` — actively triggers CI.
- `gh secret`, `gh variable`, `gh auth`.
- `gh project create|delete|field-create|field-delete` — board-shape changes.
- `make appstore-push`, `make appstore-beta`, `make appstore-screenshots`, `make appstore-bootstrap` — touch App Store Connect, fastlane state, or take a long time and burn battery.
- `git push --force`, `git push origin main`, `git reset --hard`, `rm -rf .worktrees` (Claude Code only — Cursor's allowlist matches command-prefixes, not full lines, so these need to stay in your judgement loop on Cursor).

If a future skill genuinely needs one of these, propose the allowlist diff in the same PR rather than working around it locally — `.claude/settings.json` lands automatically, and `.cursor/permissions.example.json` is the heads-up for Cursor users to re-merge with `make cursor-perms-sync`.

#### Gotcha: chained commands and `cd` shadowing

Two related traps when chaining commands with `&&`, `||`, or `;`:

**1. The leading command shadows everything after it.** Cursor (and Claude Code) match the allowlist against the leading command of the shell line, not "any command in the chain". So this:

```sh
cd /path/to/repo && gh pr create --draft --title …
```

is matched as `cd …`, **not** `gh pr create …` — the `gh pr create` allowlist entry never fires, the command runs in the sandbox, and (if network sandboxing is on) `api.github.com` is firewalled.

**2. A non-allowlisted command anywhere in the chain re-prompts.** Even if the leading command IS allowlisted, Cursor inspects the whole chain and prompts if any segment isn't covered. So this:

```sh
gh issue view 36 --repo FokkeZB/GluWink && echo '---' && gh issue view 37 --repo FokkeZB/GluWink
```

still prompts — `gh issue view` is allowlisted, but `echo` wasn't (until we added it). The fix is either to allowlist the chain segments (we did this for the common shell utilities — see "Curated set" above) or to split the chain into separate tool calls.

Fixes (in order of preference):

1. **Use the Shell tool's `working_directory` parameter** instead of `cd && …`. The system prompt for both agents documents this explicitly. The leading command is then the real one (`gh`, `git`, etc.) and the allowlist matches.
2. **Don't chain when separate calls work.** Two `gh issue view` calls as two tool invocations are unambiguously allowlisted; chained with `&& echo … &&` they're a single line that has to be re-checked end-to-end. Use chains when you actually need shell semantics (`make build 2>&1 | tail -40`), not as a way to batch unrelated reads.
3. `cd` is on the allowlist as belt-and-braces for the cases where you genuinely need a chained `cd` (e.g. inside a generated script). Prefer (1).
4. Don't chain at all when an allowlisted command can stand alone — `git push origin foo` from anywhere in the worktree works without `cd`.

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

### When the bridge goes stale

Symptom: `CallMcpTool` reports "MCP server does not exist", or the per-server `tools/` directory under `~/.cursor/projects/<project-slug>/mcps/project-*-xcode/` is missing/empty even though Xcode itself is open and `xcrun --find mcpbridge` resolves. This is the Cursor-side bridge having dropped the connection — Xcode is fine, the bridge just isn't holding a session.

Restarting MCP servers isn't an agent-side action. **Tell the owner to disable and re-enable the `xcode` MCP in Cursor Settings → MCP** (toggle off, toggle back on). That resocks the bridge and re-introspects the tool list. Confirmed working 2026-04-21. Cursor restart is the fallback if the toggle doesn't take.

Don't try to work around a stale bridge silently — flag it as soon as you notice (a subagent's build step falling back to `xcodebuild` is the usual tell), tell the owner what to do, and continue with the `xcodebuild` fallback for the current task.

## Quirks & Gotchas

**`QUIRKS.md`** (repo root) documents platform quirks, API limitations, Xcode build gotchas, and other hard-won lessons. Read it before making changes to avoid repeating mistakes.

## Forward-only by default

This is a single-maintainer repo with no external contributors and no released APIs. **Don't preserve old paths or carry compatibility shims unless a concrete in-flight regression demands it.** When a tool/library/format moves, move with it — bump the floor, delete the old code path, delete the migration story.

Concretely, when changing how something works:

- **Code:** delete the old branch, don't add a fallback "for now". If a new dev needs the old path, they'll see an error message and an upgrade command, not a quietly-different code path.
- **Skills/scripts:** assume pinned tool versions are present (see "Tool versions"). Don't write `if version < X` branches; bump the pin.
- **Docs:** describe the destination, not the journey. No "previously we used X, now we use Y" — just "we use Y". A new agent reading `AGENTS.md` from scratch should see only what's true today.
- **Commit messages and PR descriptions** are the right place for the journey: *why* the change happened, what was wrong before, alternatives considered. That history lives in `git log`, not in code or docs that future readers have to skim past.

If you catch yourself writing a "this still works for the old way" footnote, a `try/except` for a deprecated import, or a paragraph explaining what got replaced — stop and delete it. Adding context costs everyone every time they read it; deleting context costs only once.

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

**Worked example — planning loop.** After a session spent manually picking what to work on next from a 40+ issue backlog (2026-04-19), the same workflow was extracted into the **GluWink Roadmap** GH Project + `.claude/skills/plan-next/SKILL.md` — see "Self-managed planning loop" below for the full pattern.

So now "audit the site" or "what's next" is a one-liner instead of ~15 minutes of judgement calls. **When you ship the next thing that smells like this, do the same**: ship the make target (or the GH Project, or whatever the deterministic substrate is), ship the skill, mention both in the PR description, and add a one-line worked-example pointer here so future agents see the pattern.

## Self-managed planning loop

The owner defers backlog management to the agent. Workflow:

1. Owner says "work on the project" / "what's next" / "let's continue".
2. Agent re-assesses the **GluWink Roadmap** GH Project (`gh project --owner FokkeZB`, project number 1) plus open issues and PRs, proposes the next batch of 1–3 items.
3. Owner approves.
4. Agent creates one git worktree per approved issue under `.worktrees/<n>-<slug>/`, on a branch `<type>/<n>-<slug>`. Disjoint-area issues run as parallel subagents; same-area issues run serially.
5. Each subagent implements the fix in its worktree, commits per `.claude/skills/git-commit/SKILL.md`, and opens a **draft** PR with `Closes #N` in the body.
6. Owner reviews and merges. Agent moves the project card to `Done` and cleans up the worktree on the next plan-next invocation.

**The agent never merges, never pushes to `main`, never force-pushes.** Owner-in-the-loop checkpoints: batch selection, blocking subagent questions, every merge.

### Draft vs ready

`--draft` is a *temporary* state, not the resting state. Open a PR as draft only while it's genuinely incomplete or blocked — unverified on device, missing tests the owner asked for, blocked on a question relayed back, or work-in-progress between commits. **The moment the work is verified and you're ready to hand off, mark it ready for review with `gh pr ready <n>`.** This is true whether the work was done by a subagent (the parent agent reaps and marks ready, per `plan-next` step 5) or directly by the parent agent (mark ready as the final step of the same turn that opened the PR).

Leaving a verified PR in draft buries the request — GitHub hides drafts from review queues and notification roll-ups, and the owner has no signal that it's waiting on them. If the work is shippable, the PR must say so.

The full implementation lives in `.claude/skills/plan-next/SKILL.md` — including the project field IDs, the rediscovery commands if those IDs ever go stale, and the dispatch prompt template. **Read that skill before improvising new behaviour around the project board** — its conventions are how the loop stays self-consistent across sessions.

The project's structure:

| Field | Values | Notes |
|---|---|---|
| `Status` | `Backlog`, `Up Next`, `In Progress`, `In Review`, `Done` | Built-in field, options replaced via GraphQL |
| `Priority` | `P0`, `P1`, `P2`, `P3` | P0 = must-fix, P3 = someday |
| `Effort` | `XS`, `S`, `M`, `L` | XS < 1h, L = week+ |
| `Area` | mirrors repo labels | `shield`, `widgets`, `healthkit`, `nightscout`, `watchos`, `attention`, `settings`, `docs`, `infra`, `a11y`, `polish` |

**`.worktrees/`** at repo root is gitignored — it's where parallel subagents work. Inspect with `git worktree list`. Don't `rm -rf` a worktree directory directly; use `git worktree remove` so git's bookkeeping stays consistent.

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
| `criticalGlucoseThreshold` | Double (mmol/L) or absent | Main app (settings / WatchConnectivity sync) | ShieldConfig, ShieldAction, WatchApp, WatchWidget |
| `lowGlucoseThreshold` | Double (mmol/L) or absent | Main app (settings / WatchConnectivity sync) | ShieldConfig, ShieldAction, WatchApp, WatchWidget |
| `glucoseStaleMinutes` | Int or absent | Main app (settings / WatchConnectivity sync) | ShieldConfig, WatchApp, WatchWidget |
| `carbGraceHour` | Int or absent | Main app (settings / WatchConnectivity sync) | ShieldConfig, WatchApp, WatchWidget |
| `carbGraceMinute` | Int or absent | Main app (settings / WatchConnectivity sync) | ShieldConfig, WatchApp, WatchWidget |
| `glucoseUnit` | String ("mmolL" or "mgdL") or absent | Main app (settings / HealthKit auto-detect / WatchConnectivity sync) | ShieldConfig, StatusWidget, Main app, WatchApp, WatchWidget |
| `glucoseBadgeMode` | String ("off", "always", "onlyWhenAttention") or absent | Main app (settings) | Main app (badge update) |

> **Settings override precedence:** Extensions read settings keys from App Group first; if absent (never changed), they fall back to `Info.plist` values (from xcconfig). The passphrase itself is NOT in the App Group — it's in the device Keychain.

> **Validation contract (issue #84):** `criticalGlucoseThreshold > highGlucoseThreshold` is an invariant enforced **at write time** in the Settings UI via `SharedKit.SettingsValidation.validateCriticalAboveHigh`. If a user lowers the high threshold below the stored critical, or a stale value otherwise violates the invariant, the resolver **does not** silently re-clamp at read time — the Settings UI surfaces the validation error on the next save so the child / guardian is aware. `criticalGlucoseThreshold` also gates shield dismissal in `ShieldAction`: at or above critical, the shield button is labelled "treat first" and `handleAction` refuses to dismiss regardless of check-in state.

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

IF currentGlucose >= criticalGlucoseThreshold (default 20.0 mmol/L):
- Shield CANNOT be dismissed by any check-in path. The primary button is
  labelled "Treat high glucose first" and `ShieldAction.handleAction`
  refuses to dismiss regardless of acknowledgements. Re-arm interval is
  irrelevant in this state (shield never disarmed).
  Contract enforced in: `SharedKit.ShieldContent` (UI) + ShieldAction
  extension (gate). See issue #84.

ELSE IF currentGlucose > highGlucoseThreshold (default 14.0 mmol/L):
- [ ] "My glucose is high. I have taken corrective action."
- Shield CAN be dismissed after acknowledgement; re-arms after the
  configured "needs attention" interval.

IF currentGlucose < lowGlucoseThreshold (default 4.0 mmol/L):
- [ ] "My glucose is low. I am treating it now."
- Shield CAN be dismissed after acknowledgement; re-arms after the
  configured "needs attention" interval. (Lows are time-sensitive in a
  different way — there is no "critical low" counterpart in this app.)

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

**Rule:** Blue is the *welcome* variant — shown only when no data source has been configured yet (see `HomeView.showsWelcome`). Once the user has opted in to a source, in-app surfaces commit to red/green: missing or stale data with a configured source is a `needsAttention` (red) state, not a neutral one. The shield UI never reaches a no-data state because shielding can only be enabled once a data source is configured (see `ShieldManager.disableIfNoDataSource()`).

### Rules

1. **Do NOT call `UIApplication.shared.setAlternateIconName(...)`.** We deliberately do not provide alternate `.appiconset`s and do not swap the home-screen icon — it's unreliable, racy with extensions, and confuses users. The home-screen signal is the badge (see `SharedDataManager.refreshAttentionBadge()`).
2. **Use `AppIcon-Blue` / `AppIcon-Red` / `AppIcon-Green` for any surface where we control the rendering at attention-evaluation time.** Selection logic depends on the surface:
   - **In-app surfaces** (e.g. `HomeView`): welcome state (no source configured) → blue; else `needsAttention` → red; else green. Note: `ShieldContent.hasNoData` exists as a descriptive flag but is NOT the trigger — a configured source with missing data is red, not blue.
   - **Shield UI** (`ShieldConfigurationExtension`): only red / green. Shielding is gated on having a data source, so the no-data state cannot occur; if the configured source has stopped delivering, that's a `needsAttention` case (red).
   - Other examples that follow the in-app rule: future notification attachments / rich content, future widgets that want to show the brand mark with attention state.
3. **In SwiftUI inside the App target:** `Image("AppIcon-Blue")` / `Image("AppIcon-Red")` / `Image("AppIcon-Green")` works because all three are `.imageset`s in the App's asset catalog.
4. **In the ShieldConfig extension** (and any other extension that needs the variants): the App's asset catalog is **not** in the extension's bundle. Each extension that needs the artwork must ship its own copies. ShieldConfig keeps `iOS/ShieldConfig/AppIcon-Red.png` and `iOS/ShieldConfig/AppIcon-Green.png` as raw bundle resources and loads them with `UIImage(contentsOfFile: Bundle.main.path(forResource: "AppIcon-Red", ofType: "png"))`. There is intentionally no blue PNG in the extension. When adding the variants to a new extension, copy the PNGs into that target's folder; this project uses file-system synchronized groups so Xcode will pick them up automatically.
5. **Keep the artworks in sync.** When the icon is redesigned, update: `AppIcon.appiconset`, `AppIcon-Blue.imageset`, `AppIcon-Red.imageset`, `AppIcon-Green.imageset` (in both the App and Watch catalogs where they exist), and the raw PNG copies inside any extension folder. The `icons/` folder at the repo root holds the master SVGs (`iOS.svg`, `iOS-green.svg`, `iOS-red.svg`, and their `watchOS.svg` counterparts; the blue `.imageset`s reuse `iOS.png` / `watchOS.png`).

## Data Source State

The app supports three data sources for glucose / carbs: **Apple Health**, **Nightscout**, and **Demo**. Most UI (`HomeView` welcome panel, `SetupChecklistCard`, shielding gate) needs to answer "is *anything* live right now?" — and we get that wrong the moment we treat history as configuration.

**Rule:** "Has a data source" must reflect **current** state, never sticky history. Use `SharedDataManager.hasAnyDataSource` (and never re-implement the disjunction inline).

### Definitions

- **Nightscout / Demo:** straightforward — `nightscoutEnabled` / `isMockModeEnabled` are user-controlled toggles. Reading the flag is the truth.
- **Apple Health:** iOS privacy-masks read-auth status (`HKHealthStore.authorizationStatus(for:)` returns `.sharingDenied` for both "user denied" and "we never asked", and `!= .notDetermined` once we've prompted — even after the user later revokes access). So we infer "active" from sample freshness via `SharedDataManager.healthKitDeliveringRecently`: HK has delivered at least once *and* the latest stored glucose timestamp is fresher than `glucoseStaleMinutes`.
  - `healthKitEverDelivered` is kept as a stored flag, but only as the historical "we got data once" signal. Never use it as the gate for UI or shielding.

### Disable handlers MUST clean up

When the user toggles off Nightscout or Demo from Settings, the handler MUST call `SharedDataManager.handleInAppSourceDisabled()` after flipping the flag. That helper wipes the cached glucose / carb values **only** when no in-app source remains, so:

- Disabling Demo while Nightscout is still on → values stay (Nightscout will keep them fresh on the next poll).
- Disabling the last in-app source → values are cleared. If HK is still authorized + delivering, its next observer fire repopulates them within seconds; if not, the cleared state is honest and `HomeView` returns to the welcome panel.

Disable paths should also kick remaining live sources (`NightscoutManager.fetchAll()`, `HealthKitManager.refreshIfAuthorized()`) so the UI reflects the new picture immediately instead of waiting for the next poll.

The shield gate (`ShieldManager.disableIfNoDataSource()`) reads `hasAnyDataSource` too — when sources go quiet for longer than `glucoseStaleMinutes`, shielding auto-disables on the next launch / re-evaluation. That's deliberate: shielding without fresh data would treat every wake as `needsAttention` and never let the user back in.

### Welcome state UI rules

When `!hasAnyDataSource` the home screen is in *welcome* mode and must follow these rules — they keep the screen honest and focused:

- **Icon:** blue (`AppIcon-Blue`). Never red/green: with no live source there's no signal to colour against.
- **Status panel:** hidden entirely. No glucose number, no carb number, no attention checks. `HomeView.showsWelcome` returning `true` swaps the whole panel for `welcomePanel`.
- **Cached values:** wiped by `handleInAppSourceDisabled()` whenever the last in-app source is turned off. We don't ship migrations for pre-release state — disable handlers are the only thing keeping the cache honest, so they must run on every disable path.
- **Setup checklist:** *only* the data-source picker (Apple Health / Nightscout / Demo). The recommended group (shielding, passphrase, notifications) is suppressed in welcome state regardless of `setupTipsHidden`. Picking a source is the one decision that unblocks everything else; burying it under other rows dilutes the CTA.
- **`setupTipsHidden` is overridden for the data-source picker.** Even if the user previously hid the checklist, the picker reappears the moment every source goes away. They have no other path back to a working app.

Toggling a source on/off must always re-fetch (or wipe). Enable paths trigger the source's own fetch (`NightscoutManager.configurationDidChange()`, `HealthKitManager.requestAuthorization() → fetchLatest…`, `MockDataSettingsView.saveMockData()` writes directly). Disable paths run `handleInAppSourceDisabled()` + kick remaining live sources via `refreshIfAuthorized()` / `fetchAll()`. Never leave a stale value visible across a toggle.

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
