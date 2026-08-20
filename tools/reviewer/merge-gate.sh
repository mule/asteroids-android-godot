#!/usr/bin/env bash
# Decides whether a reviewed PR may be merged by the bot.
#
# This is the one irreversible step in the whole loop, so it is deliberately
# a separate, readable file rather than prose buried in an agent prompt.
# The reviewer agent MUST call this and honour its exit code:
#   exit 0 -> merge
#   exit 1 -> hold: something is wrong, label review-blocked, a human must look
#   exit 2 -> not cleared at this sha: it belongs in the review queue, not here
#
# Facts available to you (all already fetched below):
#   $pr             PR number
#   $checks         "pass" | "fail" | "pending" | "none"
#   $approvals      number of human APPROVED reviews
#   $reviewed_sha   head sha a reviewer cleared, "" if it never cleared one
#   $head_sha       head sha the PR is at right now
#   $merge_state    GitHub's mergeStateStatus (CLEAN, DIRTY, BLOCKED, ...)
#   $changed_files  number of files touched
#   $additions      lines added
#   $author         PR author login
set -euo pipefail
pr="$1"
SLUG="${REVIEW_REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"

# The namespace tools/reviewer/lease.sh's `mark-passed` writes into, via the
# shared lock primitive in tools/pool/lock.sh (its `sha` subcommand owns the
# actual ref path — no hand-copied ref format here to drift out of sync).
NS_PASSED=reviewer-passed
export POOL_REPO="$SLUG"

read -r author changed_files additions head_sha merge_state <<<"$(gh pr view "$pr" --repo "$SLUG" \
  --json author,changedFiles,additions,headRefOid,mergeStateStatus \
  -q '"\(.author.login) \(.changedFiles) \(.additions) \(.headRefOid) \(.mergeStateStatus)"')"

rollup=$(gh pr view "$pr" --repo "$SLUG" --json statusCheckRollup \
  -q '[.statusCheckRollup[]?.conclusion // .statusCheckRollup[]?.state] | @csv' 2>/dev/null || echo "")
if   [ -z "$rollup" ];                       then checks="none"
elif grep -qiE 'FAILURE|ERROR|TIMED_OUT'     <<<"$rollup"; then checks="fail"
elif grep -qiE 'PENDING|IN_PROGRESS|QUEUED'  <<<"$rollup"; then checks="pending"
else                                              checks="pass"; fi

approvals=$(gh pr view "$pr" --repo "$SLUG" --json reviews \
  -q '[.reviews[] | select(.state=="APPROVED")] | length')

labels=$(gh pr view "$pr" --repo "$SLUG" --json labels -q '[.labels[].name] | join(",")')
has_label() { grep -qE "(^|,)$1(,|\$)" <<<"$labels"; }

# The sign-off: a reviewer agent recorded a clean review at one exact head sha
# via `lease.sh mark-passed`. Pinning to the sha is the whole point. The
# `review-passed` label survives a later push; this ref does not, so a PR that
# grows new commits after its review stops clearing the gate and falls back
# into the claimable queue instead of merging on a stale label.
reviewed_sha=$(./tools/pool/lock.sh sha "$NS_PASSED" "pr-$pr")

# A missing ref does not answer with an empty string: gh writes the 404 body to
# stdout, `-q` does not filter an error response, and `|| echo ""` appends to it
# rather than replacing it. Left alone, $reviewed_sha becomes
# `{"message":"Not Found",...}` and the gate reports "reviewed at {"messa".
# It still refuses to merge, since that can never equal a head sha, but it
# refuses for a reason it cannot explain. Anything that is not a sha is "no
# review recorded", which is what a 404 actually means.
grep -qE '^[0-9a-f]{40}$' <<<"$reviewed_sha" || reviewed_sha=""

# --- merge policy -----------------------------------------------------------
# A clean agent review of the current head is the gate. Everything else below
# is a guard against merging something demonstrably broken on top of it.

# Red or still-running checks veto the merge outright. "none" is allowed
# through: this repo has no CI yet, and blocking on absent checks would mean
# nothing ever merges. Add a workflow and this arm starts biting for free.
case "$checks" in
  fail|pending) echo "gate: checks=$checks -> hold #$pr" >&2; exit 1 ;;
esac

# review-blocked means a human still owes an answer. `lease.sh mergeable`
# already filters these out, but this is the irreversible step, so it re-checks
# rather than trusting its caller to have done it.
if has_label review-blocked; then
  echo "gate: review-blocked -> hold #$pr" >&2
  exit 1
fi

# A PR that no longer merges cleanly is not a merge decision, it is a
# reconciliation decision: someone has to choose whose version of the
# conflicting code survives, and that choice is not reviewed work.
case "$merge_state" in
  DIRTY|BEHIND)
    echo "gate: mergeStateStatus=$merge_state -> #$pr conflicts with the base, needs a rebase and a fresh review" >&2
    exit 1 ;;
esac

# The actual policy: a reviewer agent cleared *this* sha. A human APPROVED
# review or the `approved` label still clear the gate too, so a person can
# always sign off on something the pool would not pass by itself.
if [ -n "$reviewed_sha" ] && [ "$reviewed_sha" = "$head_sha" ]; then
  signoff="agent-review@${head_sha:0:7}"
elif [ "$approvals" -ge 1 ]; then
  signoff="human-approval"
elif has_label approved; then
  signoff="approved-label"
elif [ -n "$reviewed_sha" ]; then
  echo "gate: reviewed at ${reviewed_sha:0:7} but head is now ${head_sha:0:7} -> #$pr needs a re-review" >&2
  exit 2
else
  echo "gate: no clean review recorded -> #$pr awaits review" >&2
  exit 2
fi

echo "gate: checks=$checks signoff=$signoff -> merge #$pr" >&2
exit 0
