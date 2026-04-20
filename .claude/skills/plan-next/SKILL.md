---
name: plan-next
description: Re-assess the GluWink Roadmap GH Project + open issues, propose the next batch of work, and — on owner approval — dispatch parallel subagents in worktrees to implement them as draft PRs. Use when the user says "work on the project", "what's next", "plan next", "let's continue", "pick up work", "what should we do next", or any variant. The skill never merges and never pushes to main; the owner stays in the loop for batch selection, blocking questions, and every merge.
allowed-tools: Bash(gh project:*), Bash(gh issue:*), Bash(gh pr:*), Bash(gh api:*), Bash(git worktree:*), Bash(git checkout:*), Bash(git branch:*), Bash(git status:*), Bash(git log:*), Bash(jq:*), Read, Write, StrReplace, Task
---

# Plan-next (GH Project → batch → worktree subagents → draft PRs)

This skill is the dispatcher for self-managed work on GluWink. The owner
says "what's next" / "work on the project" / etc., this skill reads the
state of the world, proposes a batch, and — on approval — fans out
subagents in isolated worktrees that each open a draft PR. The owner
reviews and merges. **Nothing in this skill ever merges, force-pushes,
or pushes directly to `main`.**

## When to trigger

- "work on the project"
- "what's next" / "what should we do next"
- "plan next" / "plan the next batch"
- "let's continue" / "pick up where we left off"
- "what's on the roadmap"
- Any "I'm back, drive" framing

If the user names a specific issue (e.g. "let's work on #38"), **don't
re-plan** — skip to step 4 with that single issue. Re-planning when
the user already chose the work is annoying.

## Project + repo facts

- **Repo:** `FokkeZB/GluWink`
- **Project:** "GluWink Roadmap" — `gh project --owner FokkeZB`, project number **1**, ID `PVT_kwHOACkwkc4BVH4y`
- **Status field:** `PVTSSF_lAHOACkwkc4BVH4yzhQl0Wc`
  - Backlog `1d201329` · Up Next `e7fff5ae` · In Progress `76c48375` · In Review `53d70cfd` · Done `a17042c6`
- **Priority field:** `PVTSSF_lAHOACkwkc4BVH4yzhQl1aM` (P0 `8b8e104f`, P1 `c9bab58e`, P2 `acdbd07d`, P3 `cb62c639`)
- **Effort field:** `PVTSSF_lAHOACkwkc4BVH4yzhQl1aQ` (XS `b8f01dc6`, S `30b26937`, M `abb470d9`, L `a8bd70c1`)
- **Area field:** `PVTSSF_lAHOACkwkc4BVH4yzhQl1ac` (options mirror repo labels — re-fetch with `gh project field-list` if you need a specific option ID)

If any of those IDs go stale, rediscover with:

```bash
gh project view 1 --owner FokkeZB --format json
gh project field-list 1 --owner FokkeZB --format json
```

## Workflow

### 1. Pull the world

Always parallelise these — they're independent reads:

```bash
gh project item-list 1 --owner FokkeZB --limit 100 --format json > /tmp/plan-items.json
gh issue list --repo FokkeZB/GluWink --state open --limit 100 \
  --json number,title,labels,assignees,createdAt,updatedAt,body > /tmp/plan-issues.json
gh pr list --repo FokkeZB/GluWink --state open \
  --json number,title,headRefName,isDraft,mergeable,statusCheckRollup,createdAt,updatedAt > /tmp/plan-prs.json
git -C /Users/fokkezb/Code/GluCoach log --oneline -20
```

**Reconcile.** Any open issue not in the project → add it at Backlog
before going further; the project is the source of truth and a missing
item means the planning loop has drifted.

```bash
jq -r '.items[].content.number' /tmp/plan-items.json | sort -n > /tmp/plan-on-board.txt
jq -r '.[].number' /tmp/plan-issues.json | sort -n > /tmp/plan-open.txt
comm -23 /tmp/plan-open.txt /tmp/plan-on-board.txt  # in open, not on board
```

For each missing number, `gh project item-add 1 --owner FokkeZB --url <issue-url>` then set Status=Backlog.

### 2. Re-rank

Don't trust stale `Priority` / `Effort` blindly. Factors to weigh:

- **What just shipped.** `git log` since the last plan-next run shows
  what's already in flight; don't re-pick something the owner closed
  last session.
- **Open PRs.** Any `In Review` items with a stale draft PR → surface
  to the owner ("PR #X has been open Y days — review or close?")
  before proposing new work. Don't pile on new in-progress work if the
  review queue is backing up.
- **Existing `Priority`** — but treat it as one signal. P0 always wins
  if it exists. Otherwise prefer:
  - **Bugs** (label `bug`) over enhancements when there are recent
    related commits — fixing while context is fresh is cheap.
  - **Cluster locality** — if the last shipped PR touched `widgets/`,
    a `widgets` issue is much cheaper to do next (warm context) than
    one in `healthkit/`.
  - **Unblockers** — issues whose body mentions blocking another
    issue go up. Search bodies with `jq '.[] | select(.body |
    contains("blocks #"))'`.
- **Effort fit.** Aim for a batch that fits one focused session: ~2–4
  XS/S items, OR 1 M, OR (rarely) 1 L. Never mix L with anything else.
- **Parallelism.** Items that touch disjoint areas can run as parallel
  subagents in separate worktrees. Items that touch the same files or
  the same target's `.pbxproj` should be serial.

If `Priority` is blank on most items, **the first re-rank also fills
it in** — that's expected on first invocation after the project was
created. Set Priority/Effort/Area as you decide them; the next run
benefits.

### 3. Propose

Show the owner exactly what you'd do, why, and ask. Format:

> **Proposed batch (3 items, ~one focused session):**
>
> 1. **#38** *(bug, polish)* — Icon shows blue "happy" face when
>    source is configured but data is missing → should be red.
>    *Why now:* fresh context from #4/#37 (attention-state work last
>    week). Effort XS, Area `polish`.
> 2. **#34** *(bug, widgets, nightscout)* — Widgets don't always
>    update when using Nightscout. *Why now:* P1, in cluster with #37
>    we just shipped. Effort M, Area `widgets`.
> 3. **#52** *(docs)* — Submit `gluwink.app` to GSC + Bing post-launch.
>    *Why now:* mechanical, can run in parallel with the bugs. Effort
>    XS, Area `docs`.
>
> #38 + #52 can run in parallel worktrees (disjoint areas). #34 is
> serial — touches widget extension state.
>
> **Also: PR #61 has been open 2 days. Review or close before I queue
> more `docs` work?**
>
> Approve all 3? Drop any? Substitute something else?

Use `AskQuestion` if you want a structured response; a numbered list is
fine for free-form. **Wait for explicit approval** before touching git.

### 4. Dispatch

For each approved issue, in this order:

```bash
ISSUE=38
SLUG=icon-blue-when-no-data        # short, kebab, derived from title
TYPE=fix                            # feat | fix | docs | build | chore — from primary label
BRANCH="${TYPE}/${ISSUE}-${SLUG}"
WORKTREE=".worktrees/${ISSUE}-${SLUG}"

# Create the worktree off origin/main, on a new branch
git fetch origin main
git worktree add -b "$BRANCH" "$WORKTREE" origin/main

# Move the project card to In Progress
ITEM=$(jq -r --argjson n "$ISSUE" '.items[] | select(.content.number == $n) | .id' /tmp/plan-items.json)
gh project item-edit --project-id PVT_kwHOACkwkc4BVH4y \
  --field-id PVTSSF_lAHOACkwkc4BVH4yzhQl0Wc \
  --id "$ITEM" \
  --single-select-option-id 76c48375
```

Then dispatch a subagent (`Task` with `subagent_type: generalPurpose`,
`run_in_background: true` if multiple in parallel, otherwise foreground).
The prompt **must** include:

- The full issue body (paste, don't link — subagents don't get
  conversation context).
- The branch + worktree path.
- The line `cwd is the worktree; do not cd elsewhere; do not touch
  other worktrees or the main checkout`.
- `read /Users/fokkezb/Code/GluCoach/AGENTS.md and /Users/fokkezb/Code/GluCoach/QUIRKS.md before starting`.
- `commit using the .claude/skills/git-commit/SKILL.md convention`.
- `when done, push and open a draft PR with gh pr create --draft --base main, body must end with "Closes #<issue>"`.
- `if you hit a blocking question (ambiguous spec, missing API, owner
  decision needed), DO NOT guess — return early with the question`.
- `never merge, never push to main, never force-push`.

Parallel dispatch: send multiple `Task` calls in **one** message so
they actually run concurrently, each with its own worktree.

### 5. Reap

When a subagent returns:

- **PR opened?** → Move card to `In Review` (option `53d70cfd`),
  surface the PR URL + a one-line summary to the owner.
- **Returned with a question?** → Move card back to `Up Next` (option
  `e7fff5ae`), relay the question, wait for owner answer, decide
  whether to re-dispatch (same subagent via `resume`) or fold the
  decision into the issue and re-queue later.
- **Subagent crashed / timed out?** → Leave card at `In Progress`,
  tell the owner, ask whether to retry or abandon.

After a PR is **merged by the owner** (verify with
`gh pr view <n> --json state` showing `MERGED`):

- Move card to `Done` (option `a17042c6`).
- Clean up the worktree: `git worktree remove .worktrees/<n>-<slug>`
  and delete the local branch with `git branch -D <branch>`.

Do this opportunistically at the start of the *next* plan-next
invocation (step 1), not eagerly — the owner may want the worktree
around for follow-ups.

## User-in-the-loop checkpoints — non-negotiable

The skill **must** stop and wait for the owner at:

1. **Batch selection** (step 3). Never start a worktree without
   explicit "go".
2. **Subagent blocking question** (step 5). Don't answer for the
   owner; relay verbatim.
3. **Any merge.** Subagents open drafts. The owner promotes to ready
   and merges. The skill never runs `gh pr merge`.
4. **Any push to `main`.** Forbidden. The skill works on
   `<type>/<n>-<slug>` branches only.
5. **Anything destructive on the project board** (deleting fields,
   closing the project, archiving large numbers of items). One-off
   item moves are autonomous.

## Failure modes & escapes

- **`gh project` returns 401 / missing `project` scope.** Ask the
  owner to run `gh auth refresh -h github.com -s project`. The token
  refresh is interactive (browser device flow); you can't do it for
  them.
- **Worktree path collides with an existing one.** Probably a
  half-done previous session. List with `git worktree list`, ask the
  owner before removing — could contain uncommitted work.
- **Subagent opens a PR but it doesn't link the issue.** Edit the PR
  body to add `Closes #N` so the project's "Linked pull requests"
  field auto-populates and the issue closes on merge.
- **`gh pr edit` / `gh pr view` errors with "Projects (classic) is
  being deprecated".** `gh` still queries the legacy `projectCards`
  relation on PRs and treats GitHub's deprecation warning as a hard
  error, even when you're not touching projects. Sidestep with REST:

  ```bash
  jq -Rs '{body: .}' /tmp/pr-body.md > /tmp/pr-body.json
  gh api -X PATCH repos/FokkeZB/GluWink/pulls/<n> --input /tmp/pr-body.json
  gh api repos/FokkeZB/GluWink/pulls/<n> \
    --jq '{state, draft, url, body_first_line: (.body | split("\n") | .[0])}'
  ```

  Both endpoints are covered by the repo's allowlist
  (`gh api repos/FokkeZB/` — see AGENTS.md → "Agent terminal
  allowlist").
- **Project field IDs are wrong** (someone re-created Status). Re-run
  the rediscovery commands at the top of "Project + repo facts" and
  update this file in the same PR — the IDs are baked into the skill
  on purpose so each invocation isn't a discovery dance.
- **Backlog has > 50 items and re-ranking is taking forever.** That's
  a signal to propose a *grooming* session to the owner ("the
  backlog's outgrown one-shot ranking — want me to bulk-set
  Priority/Effort/Area in a separate pass first?"). Don't try to do
  it inline.

## Don't

- Don't merge anything. Ever. Even if CI is green and the diff is
  trivial. The owner merges.
- Don't push to `main`. Branches only.
- Don't dispatch a subagent without first creating its worktree —
  parallel subagents in the same checkout will fight over `git
  status` and corrupt each other's commits.
- Don't propose batches > 3 issues. If the queue is hot and the owner
  wants more, they'll ask; over-proposing wastes the owner's
  attention.
- Don't auto-resolve subagent questions. The whole point of the
  human-in-the-loop checkpoint is that the owner decides.
- Don't update `Priority`/`Effort`/`Area` silently in bulk. If you're
  doing more than ~5 in one pass, surface the proposed labelling to
  the owner first.
- Don't re-plan when the owner asked for a specific issue. "Work on
  #38" means work on #38, not "let me reconsider the whole roadmap".
