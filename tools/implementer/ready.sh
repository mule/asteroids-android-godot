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

# Capture each source's own fetch first, separately from the "reduce it to
# a space-joined list" step, and fail CLOSED if the fetch itself failed.
# Both `lock.sh held` (see its header comment) and `gh pr list` succeed
# with empty output when there is genuinely nothing to report, and fail
# (non-zero) on an API error -- collapsing those two into one "|| true"
# would make a `gh` outage indistinguishable from "nothing is locked" /
# "no PRs are open", silently disabling the exclusion. Locks are the
# primary mutual-exclusion mechanism in this pool, so treating an outage as
# "nothing held" is exactly how two agents end up claiming the same issue;
# treating it as "nothing linked" is exactly how an agent starts work a PR
# is already in flight for. Refusing to answer is the safe failure here.
if ! locked_raw="$("$LOCK" held "$NS")"; then
  echo "ready.sh: failed to read $NS lock state (gh api error) - refusing to report readiness" >&2
  exit 1
fi
# sed/tr never fail on empty input, so no "|| true" is needed past this
# point -- the only failure mode worth guarding against was the fetch above.
locked=" $(printf '%s\n' "$locked_raw" | sed 's/^issue-//' | tr '\n' ' ') "

if ! pr_text_raw="$(gh pr list --repo "$SLUG" --state open --limit 100 --json body,title \
                       -q '.[] | "\(.title) \(.body)"')"; then
  echo "ready.sh: failed to list open PRs (gh error) - refusing to report readiness" >&2
  exit 1
fi
# Here `grep -oE` finding zero matches (no open PR mentions any issue
# number -- the common case) is a legitimate "nothing found" exit 1, not a
# fetch failure, so it's safe to swallow with "|| true" now that the fetch
# itself is already known-good.
linked=" $(printf '%s\n' "$pr_text_raw" | grep -oE '#[0-9]+' | tr -d '#' | sort -u | tr '\n' ' ' || true) "

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
    # `if`, not `[ ... ] && echo`: the latter is the loop body's LAST
    # command, so on the final-iterated issue being blocked, its own
    # non-zero test result becomes the while loop's (and thus the whole
    # pipeline's, under pipefail) exit status -- a perfectly healthy run
    # would read as a failure the moment the lowest/last open issue isn't
    # ready, which is the ordinary steady state, not an edge case. `if`
    # with no `else` always exits 0 when its condition is false.
    if [ "$blocked" = no ]; then
      echo "$n"
    fi
  done | sort -n
