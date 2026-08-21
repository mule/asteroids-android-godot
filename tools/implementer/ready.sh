#!/usr/bin/env bash
# Print epic child issues that are claimable right now, ascending.
#
# An issue is claimable when it is open, belongs to the epic, carries neither
# impl-blocked nor hold, has no open PR, is unlocked, and every issue named
# in its `## Dependencies` section is CLOSED. Strict by design: implementers
# always build on merged code, so parallelism comes from the width of the
# dependency graph rather than from speculating on unmerged branches.
#
# Dependency parsing is delegated to deps.sh, which reads one issue body on
# stdin and is pure/offline (unit-tested in isolation by
# tests/pool/test_deps.sh). deps.sh exits 2 for an UNPARSEABLE `Requires`
# clause (one naming no issue number) - that is NOT the same as "no
# dependencies", and this script must fail closed on it: an issue whose
# blockers we can't even name must never read as ready.
set -euo pipefail

# Anchored to this script's own location, not cwd, matching the convention
# tools/reviewer/lease.sh and tools/reviewer/merge-gate.sh already use for
# their sibling references to tools/pool/lock.sh: a cwd-relative path here
# would break the moment this is invoked from somewhere other than the repo
# root (coordinator loop, tests, a different worktree).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCK="$SCRIPT_DIR/../pool/lock.sh"
DEPS="$SCRIPT_DIR/deps.sh"

SLUG="${POOL_REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
EPIC="${POOL_EPIC:-43}"
NS=implementer-locks
export POOL_REPO="$SLUG"

# `|| true` on both: under pipefail, `grep -oE` finding zero matches (no
# locks held / no open PRs referencing an issue — the common case) exits 1,
# and a failing command substitution feeding a plain assignment aborts the
# whole script under `set -e`, even though "nothing matched" is not an
# error here.
locked=" $("$LOCK" held "$NS" | sed 's/^issue-//' | tr '\n' ' ' || true) "
linked=" $(gh pr list --repo "$SLUG" --state open --limit 100 --json body,title \
             -q '.[] | "\(.title) \(.body)"' | grep -oE '#[0-9]+' | tr -d '#' | sort -u | tr '\n' ' ' || true) "

gh issue list --repo "$SLUG" --state open --limit 100 \
  --json number,body,labels \
  -q '.[] | select(.body | contains("Parent epic: #'"$EPIC"'"))
          | select([.labels[].name] | index("impl-blocked") | not)
          | select([.labels[].name] | index("hold") | not)
          | "\(.number)\t\(.body | @base64)"' \
| while IFS=$'\t' read -r n body64; do
    case "$locked" in *" $n "*) continue ;; esac
    case "$linked" in *" $n "*) continue ;; esac

    deps_out=""
    deps_rc=0
    deps_out="$(printf '%s' "$body64" | base64 -d | "$DEPS")" || deps_rc=$?
    if [ "$deps_rc" -eq 2 ]; then
      continue   # UNPARSEABLE Requires clause -> fail closed, not ready
    elif [ "$deps_rc" -ne 0 ]; then
      continue   # unexpected failure -> fail closed
    fi

    blocked=no
    for dep in $deps_out; do
      state=$(gh issue view "$dep" --repo "$SLUG" --json state -q .state 2>/dev/null || echo OPEN)
      [ "$state" = "CLOSED" ] || { blocked=yes; break; }
    done
    [ "$blocked" = no ] && echo "$n"
  done | sort -n
