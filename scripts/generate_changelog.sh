#!/bin/bash
set -euo pipefail

# Generate a brief, user-facing changelog summary for the commits since the last
# release and print it as markdown bullets to stdout. Called by release.sh.
#
# The summary is written by the `claude` CLI (the release agent): it reads the
# raw commit subjects since the previous tag and distills them into a few short,
# user-facing bullets. If `claude` is unavailable or fails, we fall back to the
# cleaned-up commit subjects so a release is never blocked on the agent.
#
# Usage: generate_changelog.sh [SINCE_REF]
#   SINCE_REF  Compare against this ref (default: most recent tag from HEAD).
#              Pass "" explicitly for the very first release (whole history).

cd "$(dirname "$0")/.."

SINCE_REF="${1:-}"
if [[ -z "${1+set}" ]]; then
    # No argument at all → default to the latest tag. (An explicit empty
    # argument means "no prior tag", e.g. the first release.)
    SINCE_REF=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
fi

if [[ -n "$SINCE_REF" ]]; then
    RANGE="${SINCE_REF}..HEAD"
else
    RANGE="HEAD"
fi

# Drop release/version housekeeping commits — they're noise in a changelog.
COMMITS=$(git log "$RANGE" --no-merges --pretty=format:'%s' \
    | grep -viE '^(Release v?[0-9]|Bump version|Regenerate appcast|Update appcast|Update CHANGELOG)' \
    || true)

if [[ -z "$COMMITS" ]]; then
    echo "- Maintenance and internal improvements"
    exit 0
fi

# Fallback: raw commit subjects as bullets, capped so the list stays "brief".
raw_fallback() {
    printf '%s\n' "$COMMITS" | sed 's/^/- /' | head -6
}

if ! command -v claude >/dev/null 2>&1; then
    raw_fallback
    exit 0
fi

read -r -d '' PROMPT <<EOF || true
You are writing the release notes for PRSieve, a macOS menu bar app that triages
GitHub pull-request review requests for engineers. Below is the raw git commit
log since the last release. Write a VERY brief changelog of the major,
user-facing changes.

Rules:
- At most 4 bullets. Fewer is better — only the changes a user would notice.
- One short line per bullet, in plain language (not a commit message).
- Skip purely internal churn: refactors, tests, CI, build/release plumbing.
- Output ONLY markdown "- " bullets. No headings, no preamble, no sign-off.

Commits:
$COMMITS
EOF

# Headless run; never let an agent error abort the release.
NOTES=$(printf '%s' "$PROMPT" | claude -p 2>/dev/null || true)

# Keep only bullet lines, normalizing "*" bullets to "-", in case the model
# wraps the list in any prose.
NOTES=$(printf '%s\n' "$NOTES" | grep -E '^[[:space:]]*[-*][[:space:]]' \
    | sed -E 's/^[[:space:]]*[*][[:space:]]/- /; s/^[[:space:]]*-[[:space:]]/- /' \
    || true)

if [[ -z "$NOTES" ]]; then
    raw_fallback
else
    printf '%s\n' "$NOTES"
fi
