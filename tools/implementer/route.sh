#!/usr/bin/env bash
# Pick the implementer configuration for an issue.
#
# An `agent:<id>` label wins, so a human can steer a hard issue to the
# higher-tier model. Everything else goes to the lowest tier, which is the
# cheap default. An unknown agent falls back to the lowest tier rather than
# failing the run.
#
# Labels come from $POOL_LABELS, comma-joined, when the caller has set it
# -- including setting it to an empty string -- so tests run offline with
# no `gh` call at all. Only an UNSET POOL_LABELS triggers a live fetch.
# That distinction is `${POOL_LABELS-...}` (fires only when unset),
# deliberately not `${POOL_LABELS:-...}` (which would also fire on an
# empty-but-set value and defeat the "labels: none" test case).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROSTER="$SCRIPT_DIR/../pool/roster.sh"

n="${1:?usage: route.sh <issue-number>}"
SLUG="${POOL_REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"

# `gh issue view` writes its error to stderr (unlike `gh api`, which writes
# the error body to stdout) so `2>/dev/null` is enough to keep a fetch
# failure from leaking JSON into $labels; `|| true` on just this
# substitution keeps a fetch failure from killing the script under `set
# -e`, and degrades to "no labels" -> the cheap default tier, which is the
# safe direction to fail in here (never picks a wrong non-default agent).
labels="${POOL_LABELS-$(gh issue view "$n" --repo "$SLUG" --json labels \
          -q '[.labels[].name] | join(",")' 2>/dev/null || true)}"

want=$(printf '%s' "$labels" | tr ',' '\n' | sed -n 's/^agent://p' | head -1)

if [ -n "$want" ]; then
  row=$("$ROSTER" implementers | awk -F'\t' -v a="$want" '$1==a {print; exit}')
  if [ -n "$row" ]; then
    printf '%s\n' "$row"
    exit 0
  fi
fi

"$ROSTER" implementers | head -1
