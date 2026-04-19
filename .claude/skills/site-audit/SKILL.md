---
name: site-audit
description: Audit the GluWink marketing site (docs/) with Lighthouse and turn the findings into a tracked, fixable issue. Use when the user says "audit the site", "lighthouse the site", "check site quality", "how is the site scoring", or any variant. The skill runs the audit, summarises the result, and — if there's anything to fix — proposes to file a GH issue and implement the fixes in a branch + PR.
allowed-tools: Bash(make docs-audit:*), Bash(bash docs/scripts/lighthouse-audit.sh:*), Bash(jq:*), Bash(gh issue:*), Bash(gh pr:*), Bash(git checkout:*), Bash(git status:*), Bash(git diff:*), Read, Write, StrReplace
---

# Site Audit (Lighthouse → GH issue → fix → PR)

This skill turns the manual Lighthouse-then-fix loop into a one-prompt
workflow. The first time it ran (on 2026-04-19) it produced issue #56
and PR fixing perf 76 → 95 and a11y 96 → 100 — that's the worked
example to imitate.

## When to trigger

- "audit the site"
- "lighthouse the site" / "run lighthouse"
- "how is the site scoring?"
- "any site issues?"
- "site quality check"

If the user just asks to *re-audit* (e.g. mid-PR to verify a fix), only
do step 1 and report — skip the issue/PR proposal.

## Workflow

### 1. Run the audit

```bash
make docs-audit
```

This builds `docs/_site/` fresh, boots an isolated http server on
`:4001` (or reuses one if already up), runs Lighthouse against `/` and
`/nl/` on mobile + simulated throttling, and prints:

- A summary table (Perf / A11y / BP / SEO + LCP / FCP / TBT / CLS) per
  locale.
- A list of failing audits per locale, sorted by severity.
- Path to raw JSON reports under `/tmp/glucwink-lh/`.

The two locales should track each other closely (same template). If
they diverge, that's itself worth flagging.

### 2. Decide whether there's anything to do

**Healthy** (no action needed):

- All four categories ≥ 90 on both locales.
- No failing audits other than the known false positives we already
  filter out (`cache-insight`, `document-latency-insight`).

→ Tell the user the scores, mention the run is clean, stop.

**Action needed**:

- Any category < 90 on either locale, OR
- Any failing audit that maps to a real production concern (LCP,
  contrast, render-blocking, image-delivery, etc.).

→ Continue to step 3.

### 3. Propose to file an issue

Drill into `/tmp/glucwink-lh/*.json` with `jq` to get the *specific*
elements / URLs / numbers — vague "perf is low" issues age badly.
Useful queries:

```bash
# What was the LCP element and why was it slow?
jq '.audits["largest-contentful-paint-element"].details.items[0]' /tmp/glucwink-lh/root.json
jq '.audits["largest-contentful-paint"].details.items // .audits["largest-contentful-paint"]' /tmp/glucwink-lh/root.json

# Image delivery savings (per-URL byte counts)
jq '.audits["image-delivery-insight"].details.items[]? | {url,totalBytes,wastedBytes}' /tmp/glucwink-lh/root.json

# Colour contrast failures (specific selectors + actual ratios)
jq '.audits["color-contrast"].details.items[]? | {selector: .node.selector, snippet: .node.snippet, label: .node.nodeLabel}' /tmp/glucwink-lh/root.json
```

Then propose to the user something like:

> Lighthouse against the production-mirror build:
> | Locale | Perf | A11y | BP | SEO |
> |---|---|---|---|---|
> | / | 75 | 96 | 100 | 100 |
> | /nl/ | 76 | 96 | 100 | 100 |
>
> Same deductions both locales. Two issue clusters:
> 1. **A11y — N colour-contrast failures** (list with selectors + ratios)
> 2. **Perf — LCP X.Xs** (root cause: …)
>
> Want me to open a GH issue with the full breakdown + a fix plan, then
> branch and implement?

Wait for the user's go-ahead before writing the issue.

### 4. File the issue

Mirror the template from issue #56 — the structure that worked:

1. **Background** — locale × category score table; what tooling/throttling.
2. **A11y findings** — per-violation table (element / selector / current ratio / required ratio). Inline a CSS diff for the fix.
3. **Perf findings** — what the LCP element is, what's competing with it, byte counts. Inline the proposed HTML/JS/CSS change.
4. **Out of scope** — bigger lever (WebP, Inter font, etc.) deferred to a separate issue.
5. **Test plan** — checklist that includes "re-run `make docs-audit`" with target scores and a manual visual sanity check.

Use `gh api -X POST repos/FokkeZB/GluWink/issues --input <jsonfile>` if
the body has shell-fragile characters (backticks, `$`, etc.) — `gh
issue create --body-file` works for plain text but the API path is
robust against everything.

### 5. Branch + implement + verify + PR

```bash
git checkout -b fix/site-audit-<short-slug>-<issue-number>
# … apply the fixes specified in the issue …
make docs-audit  # confirm the scores jumped to where the issue predicted
git add -A
# Commit per .claude/skills/git-commit/SKILL.md (Conventional Commits).
git push -u origin HEAD
gh pr create --base main --fill --body-file <prbody>
```

PR body should include the **before/after** Lighthouse table — that's
the most reviewable artefact. Link it back to the issue with `Fixes
#NN`.

## Failure modes & escapes

- **`npx lighthouse` first run is slow** (~30s install on cold cache).
  Just wait. Subsequent runs are ~10s/URL.
- **Port :4001 in use by something other than `docs-publish-check`** —
  the script reuses any listener. If the listener isn't actually
  serving `docs/_site/` you'll audit the wrong thing. Tell the user;
  let them kill the offending process.
- **Headless Chrome can't find a sandbox** in some environments. The
  script already passes `--no-sandbox`. If it still fails, try
  `npx lighthouse --chrome-flags="--headless=new --no-sandbox --disable-dev-shm-usage"`.
- **Scores fluctuate ±2 points** between runs because of how Lighthouse
  simulates throttling. Don't chase a single point — focus on the
  failing-audits list.

## Don't

- Don't audit `docs-serve` (port 4000) — its live-reload script is in
  the markup and skews perf. Always audit the static `docs-publish-check`
  build.
- Don't ignore one locale because the other is clean — they share a
  template, regressions hit both.
- Don't open a PR without the before/after table; reviewers can't tell
  if the change actually moved the needle otherwise.
