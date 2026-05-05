#!/usr/bin/env bash
# Project-specific smoke greps over the built marketing site (Layer 3 of
# `make docs-check` — see #62). Asserts the structural decisions we want
# to defend at PR time, on top of what htmlproofer already covers:
#
#   - Exactly one head-level <link rel="canonical"> per real page (six
#     pages: /, /nl/, /privacy/, /nl/privacy/, /support/, /nl/support/).
#     This is the regression class that prompted the workflow — see
#     #51 / PR #114, where both a hand-rolled head.html block and
#     jekyll-seo-tag were emitting canonicals on every page.
#   - The 404 page does NOT self-canonicalise and does NOT publish an
#     og:url. Title / description / og:image stay (cheap and useful for
#     deep-link shares that 404), but it must not advertise itself as a
#     real URL. The body's nav language switcher legitimately uses an
#     <a hreflang="nl"> attribute as a navigational hint — the head-only
#     scope below makes sure we catch a head-level <link hreflang> on
#     /404.html without complaining about the nav.
#   - og:locale matches the page locale (en_US on /, nl_NL on /nl/).
#   - Every <meta property="og:image"> URL resolves to a real file in
#     _site/. htmlproofer's image check covers <img> and <source> only,
#     not og:image meta tags, so this layer owns it. The exact bug #62
#     was filed against was every page emitting an og:image pointing at
#     /assets/og-{en,nl}.png that didn't exist on disk.
#   - sitemap.xml has exactly six <loc> entries (the same six real pages).
#   - robots.txt points at the correct sitemap host.
#
# Runnable from any cwd; resolves paths relative to the repo root via
# this script's own location. Exit 0 on success, non-zero on the first
# violation (with a one-line FAIL: message naming the offending page).
#
# The build itself is not this script's job — `make docs-check` runs
# `docs-build` first. If you're invoking site-check.sh directly, make
# sure docs/_site/ is fresh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SITE="${REPO_ROOT}/docs/_site"

if [[ ! -d "${SITE}" ]]; then
  echo "FAIL: ${SITE} does not exist — run 'make docs-build' first" >&2
  exit 1
fi

REAL_PAGES=(
  "index.html"
  "nl/index.html"
  "privacy/index.html"
  "nl/privacy/index.html"
  "support/index.html"
  "nl/support/index.html"
)

fail() { echo "FAIL: $*" >&2; exit 1; }

# 1. Exactly one canonical per real page.
for p in "${REAL_PAGES[@]}"; do
  file="${SITE}/${p}"
  [[ -f "${file}" ]] || fail "${p} is missing from _site/"
  count="$(grep -cE '<link[^>]+rel="canonical"' "${file}" || true)"
  [[ "${count}" -eq 1 ]] \
    || fail "${p} has ${count} <link rel=\"canonical\"> tags (want 1) — see #51"
done

# 2. /404.html does not self-canonical.
count="$(grep -cE '<link[^>]+rel="canonical"' "${SITE}/404.html" || true)"
[[ "${count}" -eq 0 ]] \
  || fail "/404.html has ${count} <link rel=\"canonical\"> tags (want 0)"

# 3. /404.html does not advertise an og:url.
count="$(grep -cE '<meta[^>]+property="og:url"' "${SITE}/404.html" || true)"
[[ "${count}" -eq 0 ]] \
  || fail "/404.html has ${count} <meta property=\"og:url\"> tags (want 0)"

# 4. /404.html has no head-level hreflang. <a hreflang="..."> in the
# nav language switcher is fine — that's a navigational hint, not an
# SEO claim — so we scope the check to <link rel="alternate" hreflang>.
count="$(grep -cE '<link[^>]+hreflang=' "${SITE}/404.html" || true)"
[[ "${count}" -eq 0 ]] \
  || fail "/404.html has ${count} <link hreflang=...> tags (want 0)"

# 5. og:locale matches page locale.
grep -qE 'property="og:locale"[^>]+content="en_US"' "${SITE}/index.html" \
  || fail "/index.html missing og:locale=en_US"
grep -qE 'property="og:locale"[^>]+content="nl_NL"' "${SITE}/nl/index.html" \
  || fail "/nl/index.html missing og:locale=nl_NL"

# 6. Every og:image URL across the real pages + 404 resolves to a real
# file in _site/. htmlproofer skips <meta property="og:image"> entirely
# (its image check is scoped to <img> and <source>), so a missing
# og-{en,nl}.png — the original symptom of #62 — would only surface
# when someone tried to share the URL. We assert it here instead.
og_pages=("${REAL_PAGES[@]}" "404.html")
declare -a checked_paths=()
for p in "${og_pages[@]}"; do
  file="${SITE}/${p}"
  [[ -f "${file}" ]] || continue
  while IFS= read -r url; do
    [[ -z "${url}" ]] && continue
    # Strip the production hostname so we resolve the path inside _site/.
    rel="${url#https://gluwink.app}"
    rel="${rel#http://gluwink.app}"
    [[ "${rel}" == /* ]] || fail "${p} og:image URL '${url}' is not site-rooted"
    target="${SITE}${rel}"
    [[ -f "${target}" ]] \
      || fail "${p} og:image '${url}' does not resolve to a file in _site/"
    checked_paths+=("${target}")
  done < <(grep -oE '<meta[^>]+property="og:image"[^>]+content="[^"]+"' "${file}" \
             | grep -oE 'content="[^"]+"' \
             | sed -E 's/content="([^"]+)"/\1/')
done
[[ "${#checked_paths[@]}" -gt 0 ]] \
  || fail "no og:image meta tags found across ${#og_pages[@]} pages — head.html may have regressed"

# 7. sitemap has exactly the expected number of <loc> entries.
expected_locs="${#REAL_PAGES[@]}"
sitemap_locs="$(grep -c '<loc>' "${SITE}/sitemap.xml" || true)"
[[ "${sitemap_locs}" -eq "${expected_locs}" ]] \
  || fail "sitemap.xml has ${sitemap_locs} <loc> entries (want ${expected_locs})"

# 8. robots.txt points at the production sitemap.
grep -qE '^Sitemap: https://gluwink\.app/sitemap\.xml$' "${SITE}/robots.txt" \
  || fail "robots.txt is missing 'Sitemap: https://gluwink.app/sitemap.xml'"

echo "site-check.sh: all assertions passed (${#REAL_PAGES[@]} pages + 404 + ${#checked_paths[@]} og:image refs + sitemap + robots)"
