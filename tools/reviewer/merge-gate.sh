#!/usr/bin/env bash
# Decides whether a reviewed PR may be merged by the bot.
#
# This is the one irreversible step in the whole loop, so it is deliberately
# a separate, readable file rather than prose buried in an agent prompt.
# The reviewer agent MUST call this and honour its exit code:
#   exit 0 -> merge
#   exit 1 -> hold: something is wrong, label review-blocked, a human must look
#   exit 2 -> clean, only missing a sign-off: label review-passed and walk away
#
# Facts available to you (all already fetched below):
#   $pr             PR number
#   $checks         "pass" | "fail" | "pending" | "none"
#   $approvals      number of human APPROVED reviews
#   $changed_files  number of files touched
#   $additions      lines added
#   $author         PR author login
set -euo pipefail
pr="$1"
SLUG="${REVIEW_REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"

read -r author changed_files additions <<<"$(gh pr view "$pr" --repo "$SLUG" \
  --json author,changedFiles,additions -q '"\(.author.login) \(.changedFiles) \(.additions)"')"

rollup=$(gh pr view "$pr" --repo "$SLUG" --json statusCheckRollup \
  -q '[.statusCheckRollup[]?.conclusion // .statusCheckRollup[]?.state] | @csv' 2>/dev/null || echo "")
if   [ -z "$rollup" ];                       then checks="none"
elif grep -qiE 'FAILURE|ERROR|TIMED_OUT'     <<<"$rollup"; then checks="fail"
elif grep -qiE 'PENDING|IN_PROGRESS|QUEUED'  <<<"$rollup"; then checks="pending"
else                                              checks="pass"; fi

approvals=$(gh pr view "$pr" --repo "$SLUG" --json reviews \
  -q '[.reviews[] | select(.state=="APPROVED")] | length')

# GitHub refuses to let an account approve its own PR, and the agents open PRs
# as the same account that reviews them. On a single-identity repo a real
# APPROVED review is therefore unobtainable, so an explicit `approved` label
# counts as the sign-off. Add a second identity for the PRs (a bot account or
# GitHub App) and the review path above starts working on its own.
signoff=$(gh pr view "$pr" --repo "$SLUG" --json labels \
  -q 'if ([.labels[].name] | index("approved")) then "yes" else "no" end')

# --- merge policy -----------------------------------------------------------
# A human approval is the gate. Everything else is a guard against merging
# something demonstrably broken on top of that approval.

# Red or still-running checks veto the merge outright. "none" is allowed
# through: this repo has no CI yet, and blocking on absent checks would mean
# nothing ever merges. Add a workflow and this arm starts biting for free.
case "$checks" in
  fail|pending) echo "gate: checks=$checks -> hold #$pr" >&2; exit 1 ;;
esac

# The actual policy: one human APPROVED review. The reviewer agent fixed its
# own findings on this branch, so it cannot also be the thing that clears it.
if [ "$approvals" -lt 1 ] && [ "$signoff" != "yes" ]; then
  echo "gate: no approval and no \`approved\` label -> #$pr awaits sign-off" >&2
  exit 2
fi

echo "gate: checks=$checks approvals=$approvals signoff=$signoff -> merge #$pr" >&2
exit 0
