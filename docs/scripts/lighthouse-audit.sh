#!/usr/bin/env bash
# Audit the marketing site with Lighthouse and print a compact summary
# plus actionable failing audits. Used by `make docs-audit` and the
# .claude/skills/site-audit skill so anyone (human or agent) can answer
# "how is the site scoring right now?" in one command.
#
# What it does:
#   1. Builds the production site fresh (delegates to `make docs-build`).
#   2. Boots a vanilla `python3 -m http.server` on 127.0.0.1:4001 — same
#      thing `make docs-publish-check` uses, so we audit *exactly* the
#      bytes GitHub Pages will serve, not the live-reloading dev server.
#   3. Runs Lighthouse (mobile, simulated throttling) against `/` and
#      `/nl/` — both locales because the template is shared and
#      regressions tend to hit both equally.
#   4. Writes raw JSON reports to /tmp/glucwink-lh/ for follow-up
#      drilldown, and prints a human summary table + the audits that
#      failed (score < 0.9, excluding informational/manual/notApplicable
#      categories).
#
# We deliberately ignore two Lighthouse warnings:
#   - cache-insight        — python's http.server doesn't set
#                            Cache-Control. Cloudflare/GH Pages do.
#   - document-latency-insight — same reason, plus localhost RTT noise.
# Both are artifacts of the local server, not real production issues.
#
# Exit code is always 0 (informational tool). The skill / human reading
# the output decides whether to act.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SITE_DIR="${REPO_ROOT}/docs/_site"
PORT=4001
HOST=127.0.0.1
REPORT_DIR=/tmp/glucwink-lh
URLS=(
  "http://${HOST}:${PORT}/"
  "http://${HOST}:${PORT}/nl/"
)

# Tools we shell out to. `npx` will fetch lighthouse on first run.
need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing '$1' on PATH" >&2; exit 1; }; }
need python3
need npx
need jq

mkdir -p "${REPORT_DIR}"
rm -f "${REPORT_DIR}"/*.json

# Step 1 — fresh production build. Always rebuild so we audit the same
# bytes a deploy would. Cheap (sub-second) compared to the audit itself.
echo "==> Building production site (make docs-build)…"
( cd "${REPO_ROOT}" && make docs-build >/dev/null )

# Step 2 — start an http server iff one isn't already on this port. If
# the user already has `make docs-publish-check` running we just reuse
# it; otherwise we spin up our own and kill it on exit.
SERVER_PID=
cleanup() {
  if [[ -n "${SERVER_PID}" ]] && kill -0 "${SERVER_PID}" 2>/dev/null; then
    kill "${SERVER_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

if lsof -ti:"${PORT}" >/dev/null 2>&1; then
  echo "==> Reusing existing server on :${PORT}"
else
  echo "==> Starting http server on http://${HOST}:${PORT}/"
  ( cd "${SITE_DIR}" && python3 -m http.server "${PORT}" --bind "${HOST}" ) >/dev/null 2>&1 &
  SERVER_PID=$!
  # Give it a moment to bind. ~0.3s is enough on a warm machine; loop
  # to be safe on cold starts / CI.
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    sleep 0.2
    curl -fs -o /dev/null "http://${HOST}:${PORT}/" && break || true
  done
fi

# Step 3 — run Lighthouse against each URL.
echo "==> Running Lighthouse against ${#URLS[@]} URL(s)…"
for url in "${URLS[@]}"; do
  slug="$(echo "${url}" | sed "s|http://${HOST}:${PORT}||; s|/$||; s|/|_|g")"
  [[ -z "${slug}" ]] && slug="root"
  out="${REPORT_DIR}/${slug}.json"
  echo "    - ${url}  →  ${out}"
  npx --yes lighthouse "${url}" \
    --quiet \
    --chrome-flags="--headless=new --no-sandbox" \
    --output=json \
    --output-path="${out}" \
    --form-factor=mobile \
    --throttling-method=simulate \
    --only-categories=performance,accessibility,best-practices,seo \
    >/dev/null
done

# Step 4 — print a compact human summary + actionable failing audits.
# We hide the localhost-only false positives so the signal-to-noise
# stays high.
IGNORE_AUDITS_RE='^(cache-insight|document-latency-insight)$'

echo
echo "================ Lighthouse summary ================"
printf "%-12s  %-5s  %-5s  %-5s  %-5s  %-7s  %-7s  %-7s  %-5s\n" \
  "URL" "Perf" "A11y" "BP" "SEO" "FCP" "LCP" "TBT" "CLS"
echo "----------------------------------------------------"
for f in "${REPORT_DIR}"/*.json; do
  jq -r --arg name "$(basename "${f}" .json)" '
    [
      $name,
      ((.categories.performance.score*100)|round|tostring),
      ((.categories.accessibility.score*100)|round|tostring),
      ((.categories["best-practices"].score*100)|round|tostring),
      ((.categories.seo.score*100)|round|tostring),
      (.audits["first-contentful-paint"].displayValue // "n/a"),
      (.audits["largest-contentful-paint"].displayValue // "n/a"),
      (.audits["total-blocking-time"].displayValue // "n/a"),
      (.audits["cumulative-layout-shift"].displayValue // "n/a")
    ] | @tsv
  ' "${f}" \
  | awk -F'\t' '{ printf "%-12s  %-5s  %-5s  %-5s  %-5s  %-7s  %-7s  %-7s  %-5s\n", $1,$2,$3,$4,$5,$6,$7,$8,$9 }'
done
echo

for f in "${REPORT_DIR}"/*.json; do
  name="$(basename "${f}" .json)"
  echo "------ Failing audits — ${name} ------"
  jq -r --arg ignore "${IGNORE_AUDITS_RE}" '
    [ .audits | to_entries[]
      | select(.value.score != null
               and .value.score < 0.9
               and (.value.scoreDisplayMode // "") != "informative"
               and (.value.scoreDisplayMode // "") != "manual"
               and (.value.scoreDisplayMode // "") != "notApplicable")
      | select((.key | test($ignore)) | not)
    ]
    | sort_by(.value.score)
    | (if length == 0 then "  (none — clean run)" else
        (.[] | "  - \(.key)  (score=\((.value.score*100)|round))  \(.value.title)")
       end)
  ' "${f}"
  echo
done

echo "Raw reports in ${REPORT_DIR}/  (open *.json with jq, or rerun with"
echo "--output html for a browseable report)."
